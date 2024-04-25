// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './PoolFilter.sol';

contract NatureCarbonTonneFilter is PoolFilter {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address[] calldata accounts, bytes32[] calldata roles)
        external
        virtual
        initializer
    {
        __PoolFilter_init_unchained(accounts, roles);
    }
}
