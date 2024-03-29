// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity ^0.8.13;

struct FeeDistribution {
    address[] recipients;
    uint256[] shares;
}

/// @title IFeeCalculator
/// @notice This interface defines methods for calculating fees.
interface IFeeCalculator {
    /// @notice Calculates the deposit fee for a given amount.
    /// @param pool The address of the pool.
    /// @param tco2 The address of the TCO2 token.
    /// @param depositAmount The amount to be deposited.
    /// @return feeDistribution How the fee is meant to be
    /// distributed among the fee recipients.
    function calculateDepositFees(
        address pool,
        address tco2,
        uint256 depositAmount
    ) external view returns (FeeDistribution memory feeDistribution);

    /// @notice Calculates the redemption fees for a given amount.
    /// @param pool The address of the pool.
    /// @param tco2s The addresses of the TCO2 tokens.
    /// @param amounts The amounts to be redeemed.
    /// @return feeDistribution How the fee is meant to be
    /// distributed among the fee recipients.
    function calculateRedemptionFees(
        address pool,
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external view returns (FeeDistribution memory feeDistribution);
}
