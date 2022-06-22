// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <=0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

// mock class using ERC20
//slither-disable-next-line locked-ether
contract ERC20Test is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) payable ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function transferInternal(
        address from,
        address to,
        uint256 value
    ) external {
        _transfer(from, to, value);
    }

    function approveInternal(
        address owner,
        address spender,
        uint256 value
    ) external {
        _approve(owner, spender, value);
    }
}
