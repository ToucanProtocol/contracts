// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {IEcoCarbonCredit} from '../interfaces/IEcoCarbonCredit.sol';
import {PoolWithAdjustingERC1155} from './PoolWithAdjustingERC1155.sol';

/// @notice REDD pool contract
contract REDD is PoolWithAdjustingERC1155 {
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

    function initialize(address[] calldata accounts, bytes32[] calldata roles)
        external
        virtual
        initializer
    {
        __Pool_init_unchained(accounts, roles);
        __ERC20_init_unchained('REDD', 'REDD');
    }

    function _projectTokenId(address erc1155, uint256)
        internal
        view
        override
        returns (uint256)
    {
        return IEcoCarbonCredit(erc1155).projectId();
    }
}
