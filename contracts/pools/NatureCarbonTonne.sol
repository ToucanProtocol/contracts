// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {PoolWithFixedFees} from './PoolWithFixedFees.sol';

/// @notice Nature Carbon Tonne (or NatureCarbonTonne)
/// Contract is an ERC20 compliant token that acts as a pool for TCO2 tokens
contract NatureCarbonTonne is PoolWithFixedFees {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.5.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize() external virtual initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ERC20_init_unchained('Toucan Protocol: Nature Carbon Tonne', 'NCT');
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice View function to calculate fees pre-execution
    /// @dev Kept for backwards-compatibility
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// @return totalFee Total fees amount
    function calculateRedeemFees(
        address[] memory tco2s,
        uint256[] memory amounts
    ) external view virtual returns (uint256 totalFee) {
        return calculateRedemptionFees(tco2s, amounts, false);
    }
}
