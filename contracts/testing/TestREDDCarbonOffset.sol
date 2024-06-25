// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import {IEcoCarbonCredit} from '../interfaces/IEcoCarbonCredit.sol';

contract TestREDDCarbonOffset is IEcoCarbonCredit, ERC1155, Ownable {
    uint256 public immutable projectId;

    constructor(uint256 _projectId) ERC1155('test') {
        projectId = _projectId;

        uint256 initialMintAmount = 100_000_000;
        _mint(msg.sender, 1, initialMintAmount, '');
        _mint(msg.sender, 2, initialMintAmount, '');
    }
}
