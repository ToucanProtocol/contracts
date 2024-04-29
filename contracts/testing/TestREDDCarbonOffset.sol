// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import {IEcoCarbonCredit} from '../interfaces/IEcoCarbonCredit.sol';

contract TestREDDCarbonOffset is IEcoCarbonCredit, ERC1155, Ownable {
    constructor() ERC1155('test') {
        uint256 initialMintAmount = 100_000_000;
        _mint(msg.sender, 1, initialMintAmount, '');
    }

    function projectId() external pure returns (uint256) {
        return 100;
    }
}
