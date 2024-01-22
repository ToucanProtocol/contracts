// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {PoolWithFeeCalculator} from './PoolWithFeeCalculator.sol';

/// @notice Biochar pool contract
contract Biochar is PoolWithFeeCalculator {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 2;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize() external virtual initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ERC20_init_unchained('Biochar', 'CHAR');
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        // TODO: set the roles based on calldata
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
