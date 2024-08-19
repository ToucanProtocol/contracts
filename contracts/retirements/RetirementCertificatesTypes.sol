// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

struct CertificateData {
    uint256[] retirementEventIds;
    uint256 createdAt;
    address retiringEntity;
    address beneficiary;
    string retiringEntityString;
    string beneficiaryString;
    string retirementMessage;
    string beneficiaryLocation;
    string consumptionCountryCode;
    uint256 consumptionPeriodStart;
    uint256 consumptionPeriodEnd;
}

/// @dev a RetirementEvent has a clear ownership relationship.
/// This relation is less clear in an NFT that already has a beneficiary set
struct RetirementEvent {
    uint256 createdAt;
    address retiringEntity;
    /// @dev amount is denominated in 18 decimals, similar to amounts
    /// in TCO2 contracts.
    uint256 amount;
    uint256 projectVintageTokenId;
}
