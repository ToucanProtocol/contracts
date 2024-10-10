// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

struct FractionData {
    uint256 amount;
    uint256 projectVintageTokenId;
    uint256 createdAt;
    address fractioningEntity;
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

interface IRetirementCertificateFractions {
    function mintFraction(address caller, FractionData calldata fractionData)
        external
        returns (uint256);
}
