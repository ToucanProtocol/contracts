// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './bases/ToucanCarbonOffsetsFactoryBase.sol';

/// @notice The PuroToucanCarbonOffsetsFactory contract is a specific factory implementation for Puro's logic.
contract PuroToucanCarbonOffsetsFactory is ToucanCarbonOffsetsFactoryBase {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(
        address _contractRegistry,
        address[] calldata _accounts,
        bytes32[] calldata _roles
    ) external virtual initializer {
        __ToucanCarbonOffsetsFactoryBase_init(_accounts, _roles);

        contractRegistry = _contractRegistry;
    }

    function standardRegistry() public pure override returns (string memory) {
        return 'puro';
    }

    function supportedStandards()
        public
        pure
        override
        returns (string[] memory)
    {
        string[] memory standards = new string[](1);
        standards[0] = 'PURO';
        return standards;
    }
}
