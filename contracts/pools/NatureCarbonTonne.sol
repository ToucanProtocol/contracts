// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './Pool.sol';

/// @notice Nature Carbon Tonne (or NatureCarbonTonne)
/// Contract is an ERC20 compliant token that acts as a pool for TCO2 tokens
contract NatureCarbonTonne is Pool {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    string public constant VERSION = '1.4.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 2;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize() external virtual initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ERC20_init_unchained('Toucan Protocol: Nature Carbon Tonne', 'NCT');
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
