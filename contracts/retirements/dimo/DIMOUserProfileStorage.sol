// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

abstract contract DIMOUserProfileStorage {
    string public baseURI;

    address public dimoCostBasisSales;

    uint256[] internal _thresholds;
    string[] internal _tokenURIs;
    uint256 internal _tokenIndex;
}
