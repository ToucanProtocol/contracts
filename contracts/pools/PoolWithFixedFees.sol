// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Pool} from './Pool.sol';
import {Errors} from '../libraries/Errors.sol';

/// @notice Pool with fixed fees template contract
/// Any pool that inherits from this contract will be able to
// charge fixed fees on redemptions.
abstract contract PoolWithFixedFees is Pool {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event RedeemFeeUpdated(uint256 feeBp);
    event RedeemBurnFeeUpdated(uint256 feeBp);
    event RedeemRetireFeeUpdated(uint256 feeBp);
    event RedeemFeeReceiverUpdated(address receiver);
    event RedeemFeeBurnAddressUpdated(address receiver);
    event TCO2ScoringUpdated(address[] tco2s);

    // ------------------------
    // Admin functions
    // ------------------------

    /// @notice Update the fee redeem percentage
    /// @param feeBp_ percentage of fee in basis points
    function setFeeRedeemPercentage(uint256 feeBp_) external virtual {
        onlyWithRole(MANAGER_ROLE);
        require(feeBp_ < feeRedeemDivider, Errors.CP_INVALID_FEE);
        _feeRedeemPercentageInBase = feeBp_;
        emit RedeemFeeUpdated(feeBp_);
    }

    /// @notice Update the fee percentage charged in redeemManyAndRetire
    /// @param feeBp_ percentage of fee in basis points
    function setFeeRedeemRetirePercentage(uint256 feeBp_) external virtual {
        onlyWithRole(MANAGER_ROLE);
        require(feeBp_ < feeRedeemDivider, Errors.CP_INVALID_FEE);
        _feeRedeemRetirePercentageInBase = feeBp_;
        emit RedeemRetireFeeUpdated(feeBp_);
    }

    /// @notice Update the fee redeem receiver
    /// @param feeRedeemReceiver_ address to transfer the fees
    function setFeeRedeemReceiver(address feeRedeemReceiver_) external virtual {
        onlyPoolOwner();
        require(feeRedeemReceiver_ != address(0), Errors.CP_EMPTY_ADDRESS);
        _feeRedeemReceiver = feeRedeemReceiver_;
        emit RedeemFeeReceiverUpdated(feeRedeemReceiver_);
    }

    /// @notice Update the fee redeem burn percentage
    /// @param feeRedeemBurnPercentageInBase_ percentage of fee in base
    function setFeeRedeemBurnPercentage(uint256 feeRedeemBurnPercentageInBase_)
        external
        virtual
    {
        onlyPoolOwner();
        require(
            feeRedeemBurnPercentageInBase_ < feeRedeemDivider,
            Errors.CP_INVALID_FEE
        );
        _feeRedeemBurnPercentageInBase = feeRedeemBurnPercentageInBase_;
        emit RedeemBurnFeeUpdated(feeRedeemBurnPercentageInBase_);
    }

    /// @notice Update the fee redeem burn address
    /// @param feeRedeemBurnAddress_ address to transfer the fees to burn
    function setFeeRedeemBurnAddress(address feeRedeemBurnAddress_)
        external
        virtual
    {
        onlyPoolOwner();
        require(feeRedeemBurnAddress_ != address(0), Errors.CP_EMPTY_ADDRESS);
        _feeRedeemBurnAddress = feeRedeemBurnAddress_;
        emit RedeemFeeBurnAddressUpdated(feeRedeemBurnAddress_);
    }

    /// @notice Allows MANAGERs or the owner to pass an array to hold TCO2 contract addesses that are
    /// ordered by some form of scoring mechanism
    /// @param tco2s array of ordered TCO2 addresses
    function setTCO2Scoring(address[] calldata tco2s) external {
        onlyWithRole(MANAGER_ROLE);
        require(tco2s.length != 0, Errors.CP_EMPTY_ARRAY);
        scoredTCO2s = tco2s;
        emit TCO2ScoringUpdated(tco2s);
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice Return the fee recipient of redemption fees
    function feeRedeemReceiver() external view returns (address) {
        return _feeRedeemReceiver;
    }

    /// @notice Return the fee to be charged for selective redemptions
    /// in basis points
    function feeRedeemPercentageInBase() external view returns (uint256) {
        return _feeRedeemPercentageInBase;
    }

    /// @notice Return the recipient of the fee to be burnt
    function feeRedeemBurnAddress() external view returns (address) {
        return _feeRedeemBurnAddress;
    }

    /// @notice Return the fee to be burnt for selective redemptions
    /// This is calculated as a percentage of the fee charged, eg.,
    /// if the fee is 10% and the burn percentage is 40%, then the
    /// burn fee will be 4% of the total redeemed amount.
    function feeRedeemBurnPercentageInBase() external view returns (uint256) {
        return _feeRedeemBurnPercentageInBase;
    }

    function feeRedeemRetirePercentageInBase() external view returns (uint256) {
        return _feeRedeemRetirePercentageInBase;
    }

    /// @notice Deposit function for pool that accepts TCO2s and mints pool token 1:1
    /// @param tco2 TCO2 contract address to be deposited, requires approve
    /// @param amount Amount of TCO2 to be deposited
    /// @dev Eligibility is checked via `checkEligible`, balances are tracked
    /// for each TCO2 separately
    /// @return mintedPoolTokenAmount Amount of pool tokens minted to the caller
    function deposit(address tco2, uint256 amount)
        external
        returns (uint256 mintedPoolTokenAmount)
    {
        return _deposit(tco2, amount, 0);
    }

    /// @notice Redeems pool tokens for multiple underlying TCO2s 1:1 minus fees
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// Pool token in user's wallet get burned
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemMany(address[] memory tco2s, uint256[] memory amounts)
        external
        virtual
        returns (uint256[] memory redeemedAmounts)
    {
        (, redeemedAmounts) = _redeemMany(tco2s, amounts, 0, false);
    }

    /// @notice Redeems pool tokens for multiple underlying TCO2s 1:1 minus fees
    /// The redeemed TCO2s are retired in the same go in order to allow charging
    /// a lower fee vs selective redemptions that do not retire the TCO2s.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem and retire for each tco2s
    /// @return retirementIds The retirements ids that were produced
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemAndRetireMany(
        address[] memory tco2s,
        uint256[] memory amounts
    )
        external
        virtual
        returns (
            uint256[] memory retirementIds,
            uint256[] memory redeemedAmounts
        )
    {
        (retirementIds, redeemedAmounts) = _redeemMany(tco2s, amounts, 0, true);
    }

    /// @notice Automatically redeems an amount of Pool tokens for underlying
    /// TCO2s from an array of ranked TCO2 contracts
    /// starting from contract at index 0 until amount is satisfied
    /// @param amount Total amount to be redeemed
    /// @dev Pool tokens in user's wallet get burned
    /// @return tco2s amounts The addresses and amounts of the TCO2s that were
    /// automatically redeemed
    function redeemAuto(uint256 amount)
        external
        virtual
        returns (address[] memory tco2s, uint256[] memory amounts)
    {
        return redeemAuto2(amount);
    }

    /// @notice Automatically redeems an amount of Pool tokens for underlying
    /// TCO2s from an array of ranked TCO2 contracts starting from contract at
    /// index 0 until amount is satisfied.
    /// @param amount Total amount to be redeemed
    /// @return tco2s amounts The addresses and amounts of the TCO2s that were
    /// automatically redeemed
    function redeemAuto2(uint256 amount)
        public
        virtual
        returns (address[] memory tco2s, uint256[] memory amounts)
    {
        onlyUnpaused();
        require(amount != 0, Errors.CP_ZERO_AMOUNT);
        uint256 i = 0;
        // Non-zero count tracks TCO2s with a balance
        uint256 nonZeroCount = 0;

        uint256 scoredTCO2Len = scoredTCO2s.length;
        while (amount > 0 && i < scoredTCO2Len) {
            address tco2 = scoredTCO2s[i];
            uint256 balance = tokenBalances(tco2);
            uint256 amountToRedeem = 0;

            // Only TCO2s with a balance should be included for a redemption.
            if (balance != 0) {
                amountToRedeem = amount > balance ? balance : amount;
                amount -= amountToRedeem;
                unchecked {
                    ++nonZeroCount;
                }
            }

            unchecked {
                ++i;
            }

            // Create return arrays statically since Solidity does not
            // support dynamic arrays or mappings in-memory (EIP-1153).
            // Do it here to avoid having to fill out the last indexes
            // during the second iteration.
            //slither-disable-next-line incorrect-equality
            if (amount == 0) {
                tco2s = new address[](nonZeroCount);
                amounts = new uint256[](nonZeroCount);

                tco2s[nonZeroCount - 1] = tco2;
                amounts[nonZeroCount - 1] = amountToRedeem;
                redeemSingle(tco2, amountToRedeem);
            }
        }

        require(amount == 0, Errors.CP_NON_ZERO_REMAINING);

        // Execute the second iteration by avoiding to run the last index
        // since we have already executed that in the first iteration.
        nonZeroCount = 0;
        for (uint256 j = 0; j < i - 1; ++j) {
            address tco2 = scoredTCO2s[j];
            // This second loop only gets called when the `amount` is larger
            // than the first tco2 balance in the array. Here, in every iteration the
            // tco2 balance is smaller than the remaining amount while the last bit of
            // the `amount` which is smaller than the tco2 balance, got redeemed
            // in the first loop.
            uint256 balance = tokenBalances(tco2);

            // Ignore empty balances so we don't generate redundant transactions.
            //slither-disable-next-line incorrect-equality
            if (balance == 0) continue;

            tco2s[nonZeroCount] = tco2;
            amounts[nonZeroCount] = balance;
            redeemSingle(tco2, balance);
            unchecked {
                ++nonZeroCount;
            }
        }
    }

    function getScoredTCO2s() external view returns (address[] memory) {
        return scoredTCO2s;
    }
}
