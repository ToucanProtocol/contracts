// SPDX-FileCopyrightText: 2025 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import {IERC721Receiver} from '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

/**
 * @title ERC721ReceiverTest
 * @notice A mock contract that can be configured to revert on ERC721 token receipt
 */
contract ERC721ReceiverTest is IERC721Receiver {
    bool private _shouldRevert;

    constructor(bool shouldRevert_) {
        _shouldRevert = shouldRevert_;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        if (_shouldRevert) {
            revert('ERC721ReceiverTest: forced revert');
        }
        return this.onERC721Received.selector;
    }

    function setShouldRevert(bool shouldRevert_) external {
        _shouldRevert = shouldRevert_;
    }
}
