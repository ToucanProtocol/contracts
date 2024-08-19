// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import {NFTCarbonExtension} from './NFTCarbonExtension.sol';

interface IFxGenArt721 is IERC721 {
    // It returns the current supply
    // https://github.com/fxhash/fxhash-evm-core/blob/62bac5f71ebb43faea2f84d2838ebdce85b94f32/src/tokens/FxGenArt721.sol#L62
    function totalSupply() external view returns (uint96);
}

contract FxHashNFTCarbonExtension is NFTCarbonExtension {
    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address pool_) NFTCarbonExtension(pool_) {}

    function initialize(
        uint256 initialPoolTokenAllocation_,
        address erc721_,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external initializer {
        __NFTCarbonExtension_initialize(
            initialPoolTokenAllocation_,
            erc721_,
            accounts,
            roles
        );
    }

    function _getTotalSupply() internal view override returns (uint256) {
        return IFxGenArt721(address(erc721)).totalSupply();
    }
}
