// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {FeeDistribution} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';
import {PoolERC20able} from './PoolERC20able.sol';
import {Errors} from '../libraries/Errors.sol';

/// @notice Pool with fixed fees template contract
/// Any pool that inherits from this contract will be able to
// charge fixed fees on redemptions.
abstract contract PoolWithFixedFees is PoolERC20able {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event RedeemFeeUpdated(uint256 feeBp);
    event RedeemRetireFeeUpdated(uint256 feeBp);
    event RedeemFeeReceiverUpdated(address receiver);
    event TCO2ScoringUpdated(address[] tco2s);

    // ------------------------
    // Admin functions
    // ------------------------

    /// @notice Update the fee redeem percentage
    /// @param feeBp_ percentage of fee in basis points
    function setFeeRedeemPercentage(uint256 feeBp_) external {
        onlyWithRole(MANAGER_ROLE);
        require(feeBp_ < feeRedeemDivider, Errors.CP_INVALID_FEE);
        _feeRedeemPercentageInBase = feeBp_;
        emit RedeemFeeUpdated(feeBp_);
    }

    /// @notice Update the fee percentage charged in redeemManyAndRetire
    /// @param feeBp_ percentage of fee in basis points
    function setFeeRedeemRetirePercentage(uint256 feeBp_) external {
        onlyWithRole(MANAGER_ROLE);
        require(feeBp_ < feeRedeemDivider, Errors.CP_INVALID_FEE);
        _feeRedeemRetirePercentageInBase = feeBp_;
        emit RedeemRetireFeeUpdated(feeBp_);
    }

    /// @notice Update the fee redeem receiver
    /// @param feeRedeemReceiver_ address to transfer the fees
    function setFeeRedeemReceiver(address feeRedeemReceiver_) external {
        onlyPoolOwner();
        require(feeRedeemReceiver_ != address(0), Errors.CP_EMPTY_ADDRESS);
        _feeRedeemReceiver = feeRedeemReceiver_;
        emit RedeemFeeReceiverUpdated(feeRedeemReceiver_);
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

    /// @notice View function to calculate deposit fees pre-execution
    /// Note that currently no deposit fees are charged.
    /// @dev User specifies in front-end the address and amount they want
    /// First param is the TCO2 contract address to be deposited
    /// Second param is the amount of TCO2 to be deposited
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateDepositFees(address, uint256)
        external
        view
        override
        returns (uint256 feeDistributionTotal)
    {
        onlyUnpaused();

        return 0;
    }

    /// @notice View function to calculate fees pre-execution,
    /// according to the amounts of pool tokens to be spent.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of pool token amounts to spend in order to redeem TCO2s.
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionInFees(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    ) public view override returns (uint256 feeDistributionTotal) {
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(tco2s);
        (uint256[] memory feeAmounts, ) = _calculateRedemptionInFees(
            vintages,
            amounts,
            toRetire
        );
        for (uint256 i = 0; i < feeAmounts.length; ++i) {
            feeDistributionTotal += feeAmounts[i];
        }
    }

    function _calculateRedemptionInFees(
        PoolVintageToken[] memory vintages,
        uint256[] memory amounts,
        bool toRetire
    )
        internal
        view
        override
        returns (
            uint256[] memory feeAmounts,
            FeeDistribution memory feeDistribution
        )
    {
        onlyUnpaused();

        uint256 vintageLength = vintages.length;
        _checkLength(vintageLength, amounts.length);

        // Exempted addresses pay no fees
        if (redeemFeeExemptedAddresses[msg.sender]) {
            return (
                new uint256[](vintageLength),
                FeeDistribution(new address[](0), new uint256[](0))
            );
        }

        uint256 feeDistributionTotal = 0;
        feeAmounts = new uint256[](vintageLength);
        for (uint256 i = 0; i < vintageLength; ++i) {
            uint256 feeAmount = getFixedRedemptionFee(amounts[i], toRetire);
            feeDistributionTotal += feeAmount;
            feeAmounts[i] = feeAmount;
        }
        feeDistribution = getFixedRedemptionFeeRecipients(feeDistributionTotal);
    }

    /// @notice View function to calculate fees pre-execution,
    /// according to the amounts of TCO2 to be redeemed.
    /// @dev User specifies in front-end the addresses and amounts they want
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts of TCO2 to be redeemed
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionOutFees(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    ) external view override returns (uint256 feeDistributionTotal) {
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(tco2s);
        (feeDistributionTotal, ) = _calculateRedemptionOutFees(
            vintages,
            amounts,
            toRetire
        );
    }

    function _calculateRedemptionOutFees(
        PoolVintageToken[] memory vintages,
        uint256[] memory amounts,
        bool toRetire
    )
        internal
        view
        override
        returns (
            uint256 feeDistributionTotal,
            FeeDistribution memory feeDistribution
        )
    {
        onlyUnpaused();

        uint256 vintageLength = vintages.length;
        _checkLength(vintageLength, amounts.length);

        // Exempted addresses pay no fees
        if (redeemFeeExemptedAddresses[msg.sender]) {
            return (0, FeeDistribution(new address[](0), new uint256[](0)));
        }

        for (uint256 i = 0; i < vintageLength; ++i) {
            feeDistributionTotal += getFixedRedemptionFee(amounts[i], toRetire);
        }
        feeDistribution = getFixedRedemptionFeeRecipients(feeDistributionTotal);
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
        return _deposit(_buildPoolVintageToken(tco2), amount, 0);
    }

    /// @notice Redeem TCO2s for pool tokens 1:1 minus fees
    /// The amounts provided are the exact amounts of pool tokens the caller
    /// is willing to spend in order to redeem TCO2s.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of pool token amounts to spend in order to redeem TCO2s.
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemInMany(address[] memory tco2s, uint256[] memory amounts)
        external
        virtual
        returns (uint256[] memory redeemedAmounts)
    {
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(tco2s);
        (, redeemedAmounts) = _redeemInMany(vintages, amounts, 0, false);
    }

    /// @notice Redeem TCO2s for pool tokens 1:1 minus fees
    /// The amounts provided are the exact amounts of TCO2s to be redeemed.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of TCO2 amounts to redeem
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @return poolAmountSpent The amount of pool tokens spent by the caller
    function redeemOutMany(address[] memory tco2s, uint256[] memory amounts)
        external
        virtual
        returns (uint256 poolAmountSpent)
    {
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(tco2s);
        (, poolAmountSpent) = _redeemOutMany(vintages, amounts, 0, false);
    }

    /// @notice Redeem and retire TCO2s for pool tokens 1:1 minus fees
    /// The amounts provided are the exact amounts of pool tokens the caller
    /// is willing to spend in order to retire TCO2s.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of pool token amounts to spend in order to redeem
    /// and retire TCO2s. The indexes of this array are matching 1:1 with the
    /// tco2s array.
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
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(tco2s);
        (retirementIds, redeemedAmounts) = _redeemInMany(
            vintages,
            amounts,
            0,
            true
        );
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
            uint256 balance = tokenBalance(tco2);
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
                //slither-disable-next-line unused-return
                _redeemSingle(_buildPoolVintageToken(tco2), amountToRedeem);
            }
        }

        if (amount != 0) {
            revert(Errors.CP_NON_ZERO_REMAINING);
        }

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
            uint256 balance = tokenBalance(tco2);

            // Ignore empty balances so we don't generate redundant transactions.
            //slither-disable-next-line incorrect-equality
            if (balance == 0) continue;

            tco2s[nonZeroCount] = tco2;
            amounts[nonZeroCount] = balance;
            //slither-disable-next-line unused-return
            _redeemSingle(_buildPoolVintageToken(tco2), balance);
            unchecked {
                ++nonZeroCount;
            }
        }
    }

    function getScoredTCO2s() external view returns (address[] memory) {
        return scoredTCO2s;
    }

    function getFixedRedemptionFee(uint256 amount, bool toRetire)
        internal
        view
        returns (uint256)
    {
        // Use appropriate fee bp to charge
        uint256 feeBp = 0;
        if (toRetire) {
            feeBp = _feeRedeemRetirePercentageInBase;
        } else {
            feeBp = _feeRedeemPercentageInBase;
        }
        // Calculate fee
        return (amount * feeBp) / feeRedeemDivider;
    }

    function getFixedRedemptionFeeRecipients(uint256 totalFee)
        internal
        view
        returns (FeeDistribution memory feeDistribution)
    {
        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);
        recipients[0] = _feeRedeemReceiver;
        shares[0] = totalFee;
        return FeeDistribution(recipients, shares);
    }
}
