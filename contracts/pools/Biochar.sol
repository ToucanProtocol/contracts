// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {PoolBridgeable} from './PoolBridgeable.sol';
import {PoolWithFeeCalculatorERC20} from './PoolWithFeeCalculatorERC20.sol';

/// @notice Biochar pool contract
contract Biochar is PoolWithFeeCalculatorERC20, PoolBridgeable {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 4;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address[] calldata accounts, bytes32[] calldata roles)
        external
        virtual
        initializer
    {
        __Pool_init_unchained(accounts, roles);
        __ERC20_init_unchained('Biochar', 'CHAR');
    }

    /// @dev Exposed for backwards compatibility and will be removed
    /// in a future version. Use totalProjectSupply instead.
    function totalPerProjectTCO2Supply(uint256 projectTokenId)
        external
        view
        returns (uint256)
    {
        return totalProjectSupply[projectTokenId];
    }

    /// @dev Exposed for backwards compatibility and will be removed
    /// in a future version. Use tokenBalance instead.
    function tokenBalances(address tco2) public view returns (uint256) {
        return tokenBalance(tco2);
    }

    /// @dev Exposed for backwards compatibility and will be removed
    /// in a future version. Use totalUnderlyingSupply instead.
    function totalTCO2Supply() external view returns (uint256) {
        return totalUnderlyingSupply;
    }
}
