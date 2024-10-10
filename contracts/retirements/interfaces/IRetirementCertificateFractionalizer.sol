// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

struct FractionRequestData {
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

interface IRetirementCertificateFractionalizer {
    function mintFraction(FractionRequestData calldata params)
        external
        returns (uint256 tokenId);

    function mintFractionFrom(address from, FractionRequestData calldata params)
        external
        returns (uint256 tokenId);
}
