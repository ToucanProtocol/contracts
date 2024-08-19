// SPDX-License-Identifier: Apache-2.0

// This contract is based on the original work by enjin:
// https://github.com/enjin/erc-1155/blob/master/contracts/ERC1155AllowanceWrapper.sol
// The original work is licensed under the Apache License, Version 2.0
// You may obtain a copy of the License at:
// http://www.apache.org/licenses/LICENSE-2.0

// SPDX-FileCopyrightText: 2024 Toucan Labs

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';

/// @title ERC1155Allowable
/// @notice This contract is a wrapper around the ERC1155 contract to allow for
/// specific allowances to be set for each token ID, expanding the ERC1155 standard
/// which only allows for a global allowance to be set for all token IDs.
abstract contract ERC1155Allowable is ERC1155Upgradeable {
    // from => operator => token id => allowance
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public allowances;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id,
        uint256 oldValue,
        uint256 amount
    );

    /// @notice Approve an address to spend a specific amount of a Token
    /// @param spender The address allowed to spend
    /// @param id ID of the Token
    /// @param currentAmount The current spending limit
    /// @param amount The new spending limit
    function approve(
        address spender,
        uint256 id,
        uint256 currentAmount,
        uint256 amount
    ) external {
        require(
            allowances[_msgSender()][spender][id] == currentAmount,
            'ERC1155Allowable: invalid current amount'
        );
        allowances[_msgSender()][spender][id] = amount;

        emit Approval(_msgSender(), spender, id, currentAmount, amount);
    }

    /// @notice Transfer a single Token from one address to another. The caller
    /// must be the owner, approved for all or have a sufficient allowance.
    /// @param from Source address
    /// @param to Target address
    /// @param id ID of the Token
    /// @param amount Transfer amount
    /// @param data Additional data with no specified format
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        if (from != _msgSender() && !isApprovedForAll(from, _msgSender())) {
            _decreaseAllowance(from, _msgSender(), id, amount);
        }
        _safeTransferFrom(from, to, id, amount, data);
    }

    /// @notice Transfer a batch of Tokens from one address to another. The caller
    /// must be the owner, approved for all or have sufficient allowances.
    /// @param from Source address
    /// @param to Target address
    /// @param ids IDs of the Tokens
    /// @param amounts Transfer amounts
    /// @param data Additional data with no specified format
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        if (_msgSender() != from && !isApprovedForAll(from, _msgSender())) {
            uint256 length = ids.length;
            for (uint256 i = 0; i < length; ++i) {
                _decreaseAllowance(from, _msgSender(), ids[i], amounts[i]);
            }
        }
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function _decreaseAllowance(
        address from,
        address spender,
        uint256 id,
        uint256 amount
    ) internal {
        uint256 allowance = allowances[from][spender][id];
        require(
            allowance >= amount,
            'ERC1155Allowable: caller has no sufficient allowance'
        );
        unchecked {
            allowances[from][spender][id] = allowance - amount;
        }
    }
}
