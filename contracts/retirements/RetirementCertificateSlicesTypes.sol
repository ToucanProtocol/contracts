// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

struct SliceData {
    uint256 amount;
    uint256 projectVintageTokenId;
    uint256 createdAt;
    address slicingEntity;
    address beneficiary;
    string beneficiaryString;
    string retirementMessage;
    string beneficiaryLocation;
    string consumptionCountryCode;
    uint256 consumptionPeriodStart;
    uint256 consumptionPeriodEnd;
    string tokenURI;
    bytes extraData;
}

struct SliceRequestData {
    uint256 amount;
    uint256 projectVintageTokenId;
    address beneficiary;
    string beneficiaryString;
    string retirementMessage;
    string beneficiaryLocation;
    string consumptionCountryCode;
    uint256 consumptionPeriodStart;
    uint256 consumptionPeriodEnd;
    string tokenURI;
    bytes extraData;
}
