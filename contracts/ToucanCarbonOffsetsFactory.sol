// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

// ============ External Imports ============
import './bases/ToucanCarbonOffsetsFactoryBase.sol';

/// @notice This TCO2 factory creates project-vintage-specific ERC20 contracts for Batch-NFT fractionalization
/// Locks in received ERC721 Batch-NFTs and can mint corresponding quantity of ERC20s
/// Permissionless, anyone can deploy new ERC20s unless they do not yet exist and pid exists
contract ToucanCarbonOffsetsFactory is ToucanCarbonOffsetsFactoryBase {
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.3.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address _contractRegistry)
        external
        virtual
        initializer
    {
        // TODO(LILA-5187): Remove all init below in favor of __ToucanCarbonOffsetsFactoryBase_init
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();

        contractRegistry = _contractRegistry;
    }

    function standardRegistry() public pure override returns (string memory) {
        return 'verra';
    }

    function supportedStandards()
        public
        pure
        override
        returns (string[] memory)
    {
        string[] memory standards = new string[](1);
        standards[0] = 'VCS';
        return standards;
    }
}
