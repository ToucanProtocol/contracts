// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './bases/ToucanCarbonOffsetsEscrowableWithBatchBase.sol';

/// @notice The PuroToucanCarbonOffsets contract is a specific implementation for Puro's logic.
contract PuroToucanCarbonOffsets is ToucanCarbonOffsetsEscrowableWithBatchBase {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.3.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    // ----------------------------------------
    //       Upgradable related functions
    // ----------------------------------------

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 projectVintageTokenId_,
        address contractRegistry_
    ) external virtual initializer {
        __ERC20_init_unchained(name_, symbol_);
        _projectVintageTokenId = projectVintageTokenId_;
        contractRegistry = contractRegistry_;
    }

    function standardRegistry() public pure override returns (string memory) {
        return 'puro';
    }

    function standardRegistryDecimals() public pure override returns (uint8) {
        return 18;
    }
}
