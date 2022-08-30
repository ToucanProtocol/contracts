// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract TestToken is ERC20, Ownable {
    address public router;

    event RouterUpdated(address router);

    modifier onlyRouter() {
        require(msg.sender == router, 'Only router can functionality');
        _;
    }

    constructor() ERC20('TestToken', 'TT') {
        uint256 initialMintAmount = 100_000_000;
        _mint(msg.sender, initialMintAmount);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), 'Router cannot be zero address');
        router = _router;
        emit RouterUpdated(router);
    }

    function bridgeBurn(address _account, uint256 _amount) external onlyRouter {
        _burn(_account, _amount);
    }

    function bridgeMint(address _account, uint256 _amount) external onlyRouter {
        _mint(_account, _amount);
    }
}
