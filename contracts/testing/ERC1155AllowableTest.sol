// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '../token/ERC1155Allowable.sol';

/// @title ERC1155AllowableTest
/// @notice This contract is a wrapper around the abstract ERC1155Allowable contract
/// to allow for testing of ERC1155Allowable's functions
contract ERC1155AllowableTest is ERC1155Allowable {
    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) external {
        _mint(account, id, amount, '');
    }
}
