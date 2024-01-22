// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {IFeeCalculator} from './interfaces/IFeeCalculator.sol';
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

    /// @notice Returns the total TCO2 supply of the pool
    function totalTCO2Supply() external view returns (uint256) {
        return _totalTCO2Supply;
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

    /// @notice Redeems pool tokens for multiple underlying TCO2s 1:1 minus fees
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each TCO2s
    /// Pool token in user's wallet get burned
    /// @param maxFee Maximum fee to be paid for the redemption. This value cannot be zero.
    /// Use `calculateRedemptionFees(tco2s,amounts,false)` to determine the fee that will
    /// be charged given the state of the pool during this call. Add a buffer on top of the
    /// returned fee amount up to the maximum fee you are willing to pay.
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemMany(
        address[] memory tco2s,
        uint256[] memory amounts,
        uint256 maxFee
    ) external virtual returns (uint256[] memory redeemedAmounts) {
        require(maxFee != 0, Errors.CP_INVALID_MAX_FEE);
        require(tco2s.length == 1, Errors.CP_NOT_SUPPORTED);
        (, redeemedAmounts) = _redeemMany(tco2s, amounts, maxFee, false);
    }
}
