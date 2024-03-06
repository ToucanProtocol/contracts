// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {FeeDistribution, IFeeCalculator} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

import {Pool} from './Pool.sol';
import {Errors} from '../libraries/Errors.sol';

/// @notice Pool with fee calculator template contract
/// Any pool that inherits from this contract will be able to
// charge fees both on deposits and redemptions with the use
/// of a fee calculator contract.
abstract contract PoolWithFeeCalculator is Pool {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event FeeCalculatorUpdated(address feeCalculator);

    // ------------------------
    // Admin functions
    // ------------------------

    /// @notice Update the address of the fee module contract
    /// @param _feeCalculator Fee module contract address
    function setFeeCalculator(address _feeCalculator) external {
        onlyPoolOwner();
        feeCalculator = IFeeCalculator(_feeCalculator);
        emit FeeCalculatorUpdated(_feeCalculator);
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice View function to calculate deposit fees pre-execution
    /// @dev User specifies in front-end the address and amount they want
    /// @param tco2 TCO2 contract address
    /// @param amount Amount to redeem
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateDepositFees(address tco2, uint256 amount)
        external
        view
        override
        returns (uint256 feeDistributionTotal)
    {
        onlyUnpaused();

        FeeDistribution memory feeDistribution = feeCalculator
            .calculateDepositFees(address(this), tco2, amount);
        feeDistributionTotal = getFeeDistributionTotal(feeDistribution);
    }

    /// @notice View function to calculate fees pre-execution
    /// NOTE: This function is not supported yet
    function calculateRedemptionInFees(
        address[] memory, /* tco2s */
        uint256[] memory, /* amounts */
        bool /* toRetire */
    )
        external
        pure
        override
        returns (
            uint256 /* feeDistribution */
        )
    {
        revert(Errors.CP_NOT_SUPPORTED);
    }

    function _calculateRedemptionInFees(
        address[] memory, /* tco2s */
        uint256[] memory, /* amounts */
        bool /* toRetire */
    )
        internal
        pure
        override
        returns (
            uint256[] memory, /* feeAmounts */
            FeeDistribution memory /* feeDistribution */
        )
    {
        revert(Errors.CP_NOT_SUPPORTED);
    }

    /// @notice View function to calculate fees pre-execution
    /// @dev User specifies in front-end the addresses and amounts they want
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of TCO2 amounts to redeem
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case. Currently not supported.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionOutFees(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    ) external view override returns (uint256 feeDistributionTotal) {
        (feeDistributionTotal, ) = _calculateRedemptionOutFees(
            tco2s,
            amounts,
            toRetire
        );
    }

    function _calculateRedemptionOutFees(
        address[] memory tco2s,
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
        // Calculating fees for retiring is not supported yet
        require(!toRetire, Errors.CP_NOT_SUPPORTED);
        // Calculating fees for multi-TCO2 redemptions is not supported yet
        uint256 tco2Length = tco2s.length;
        require(tco2Length == 1, Errors.CP_NOT_SUPPORTED);
        require(tco2Length == amounts.length, Errors.CP_LENGTH_MISMATCH);

        // Exempted addresses pay no fees
        if (redeemFeeExemptedAddresses[msg.sender]) {
            return (0, FeeDistribution(new address[](0), new uint256[](0)));
        }

        feeDistribution = feeCalculator.calculateRedemptionFees(
            address(this),
            tco2s,
            amounts
        );
        feeDistributionTotal = getFeeDistributionTotal(feeDistribution);
    }

    /// @notice Deposit function for pool that accepts TCO2s and mints pool token 1:1
    /// @param tco2 TCO2 to be deposited, requires approve
    /// @param amount Amount of TCO2 to be deposited
    /// @param maxFee Maximum fee to be paid for the deposit. This value cannot be zero.
    /// Use `calculateDepositFees(tco2,amount)` to determine the fee that will be charged
    /// given the state of the pool during this call. Add a buffer on top of the returned
    /// fee amount up to the maximum fee you are willing to pay.
    /// @dev Eligibility of the ERC20 token to be deposited is checked via `checkEligible`
    /// @return mintedPoolTokenAmount Amount of pool tokens minted to the caller
    function deposit(
        address tco2,
        uint256 amount,
        uint256 maxFee
    ) external returns (uint256 mintedPoolTokenAmount) {
        require(maxFee != 0, Errors.CP_INVALID_MAX_FEE);
        return _deposit(tco2, amount, maxFee);
    }

    /// @notice Redeem TCO2s for pool tokens 1:1 minus fees
    /// The amounts provided are the exact amounts of TCO2s to be redeemed.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of TCO2 amounts to redeem
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @param maxFee Maximum fee to be paid for the redemption. This value cannot be zero.
    /// Use `calculateRedemptionOutFees(tco2s,amounts,false)` to determine the fee that will
    /// be charged given the state of the pool during this call. Add a buffer on top of the
    /// returned fee amount up to the maximum fee you are willing to pay.
    /// @return poolAmountSpent The amount of pool tokens that were spent
    function redeemOutMany(
        address[] memory tco2s,
        uint256[] memory amounts,
        uint256 maxFee
    ) external virtual returns (uint256 poolAmountSpent) {
        require(maxFee != 0, Errors.CP_INVALID_MAX_FEE);
        require(tco2s.length == 1, Errors.CP_NOT_SUPPORTED);
        (, poolAmountSpent) = _redeemOutMany(tco2s, amounts, maxFee, false);
    }
}
