// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Errors} from '../libraries/Errors.sol';
import {PoolBridgeable} from './PoolBridgeable.sol';
import {PoolWithFixedFees} from './PoolWithFixedFees.sol';

/// @notice Nature Carbon Tonne (or NatureCarbonTonne)
/// Contract is an ERC20 compliant token that acts as a pool for TCO2 tokens
contract NatureCarbonTonne is PoolWithFixedFees, PoolBridgeable {
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
    /// @dev Kept for backwards-compatibility. New clients should use
    /// calculateRedemptionInFees instead.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// @return totalFee Total fees amount
    function calculateRedeemFees(
        address[] memory tco2s,
        uint256[] memory amounts
    ) external view virtual returns (uint256 totalFee) {
        return calculateRedemptionInFees(tco2s, amounts, false);
    }

    /// @notice Need to set the total TCO2 supply of the pool and
    /// the supply for each project token held by the pool
    /// otherwise redemptions and crosschain rebalancing will fail.
    /// This function will be executed once then removed in a future
    /// upgrade.
    /// @param projectTokenIds Project token ids held by the pool
    /// @param projectSupply Total project supply held by the pool.
    /// The indexes of this array are matching 1:1 with the
    /// projectTokenIds array.
    function setTotalTCO2Supply(
        uint256[] calldata projectTokenIds,
        uint256[] calldata projectSupply
    ) external {
        onlyWithRole(MANAGER_ROLE);
        uint256 projectTokenIdsLen = projectTokenIds.length;
        require(
            projectTokenIdsLen == projectSupply.length,
            Errors.CP_LENGTH_MISMATCH
        );
        require(projectTokenIdsLen != 0, Errors.CP_EMPTY_ARRAY);

        uint256 _totalUnderlyingSupply = 0;
        for (uint256 i = 0; i < projectTokenIdsLen; ++i) {
            // Does not protect against duplicates
            _totalUnderlyingSupply += projectSupply[i];
            totalProjectSupply[projectTokenIds[i]] = projectSupply[i];
        }
        totalUnderlyingSupply = _totalUnderlyingSupply;
    }

    /// @notice Redeem TCO2s for pool tokens 1:1 minus fees
    /// The amounts provided are the exact amounts of pool tokens the caller
    /// is willing to spend in order to redeem TCO2s.
    /// @dev Kept for backwards-compatibility. New clients should use
    /// redeemInMany instead.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of pool token amounts to spend in order to redeem TCO2s.
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemMany(address[] memory tco2s, uint256[] memory amounts)
        external
        virtual
        returns (uint256[] memory redeemedAmounts)
    {
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(tco2s);
        (, redeemedAmounts) = _redeemInMany(vintages, amounts, 0, false);
    }

    /// @notice Returns the balance of the carbon offset found in the pool
    /// @dev Kept for backwards compatibility. Use tokenBalance instead.
    /// @param tco2 TCO2 contract address
    /// @return balance pool balance
    function tokenBalances(address tco2) public view returns (uint256) {
        return tokenBalance(tco2);
    }
}
