// SPDX-FileCopyrightText: 2025 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import {OptionalSafeMintERC721Upgradeable} from '../retirements/extensions/OptionalSafeMintERC721Upgradeable.sol';

/**
 * @title OptionalSafeMintERC721Test
 * @notice Test contract that exposes the internal _optionalSafeMint functions from OptionalSafeMintERC721Upgradeable
 * for unit testing purposes.
 */
contract OptionalSafeMintERC721Test is OptionalSafeMintERC721Upgradeable {
    function initialize() external initializer {
        __ERC721_init('OptionalSafeMintERC721Test', 'TEST');
    }

    function optionalSafeMintWithData(
        address to,
        uint256 tokenId,
        bytes memory data,
        bool skipRevert
    ) external {
        _optionalSafeMint(to, tokenId, data, skipRevert);
    }

    function optionalSafeMint(
        address to,
        uint256 tokenId,
        bool skipRevert
    ) external {
        _optionalSafeMint(to, tokenId, skipRevert);
    }
}
