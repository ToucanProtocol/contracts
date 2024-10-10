// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../../interfaces/IToucanContractRegistry.sol';
import './interfaces/IDIMOUserProfile.sol';

struct VintageListing {
    uint256 amount;
    uint256 pricePerUnit;
}

abstract contract DIMOCostBasisSalesStorage {
    uint256 internal _totalSold;
    mapping(uint256 => mapping(address => VintageListing)) public listing;

    IToucanContractRegistry public contractRegistry;
    IERC20 public paymentToken;
    IDIMOUserProfile public dimoUserProfile;

    address public lister;
}
