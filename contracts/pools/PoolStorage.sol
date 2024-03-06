// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {IFeeCalculator} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

abstract contract PoolStorageV1 {
    /// @notice The supply cap is used as a measure to guard deposits
    /// in the pool. It is meant to minimize the impact a potential
    /// compromise in the source registry (eg. Verra) can have to the pool.
    uint256 public supplyCap;
    //slither-disable-next-line constable-states
    mapping(address => uint256) private DEPRECATED_tokenBalances;
    //slither-disable-next-line constable-states
    address private DEPRECATED_contractRegistry;

    /// @notice array used to read from when redeeming TCO2s automatically
    address[] public scoredTCO2s;

    /// @dev Mappings for attributes that can be included or excluded
    /// if set to `false`, attribute-values are blacklisted/rejected
    /// if set to `true`, attribute-values are whitelisted/accepted
    //slither-disable-next-line constable-states
    mapping(string => bool) private DEPRECATED_regions;
    //slither-disable-next-line constable-states
    mapping(string => bool) private DEPRECATED_standards;
    //slither-disable-next-line constable-states
    mapping(string => bool) private DEPRECATED_methodologies;

    /// @dev mapping to whitelist external non-TCO2 contracts by address
    //slither-disable-next-line constable-states
    mapping(address => bool) private DEPRECATED_externalWhiteList;

    /// @dev mapping to include certain TCO2 contracts by address,
    /// overriding attribute matching checks
    //slither-disable-next-line constable-states
    mapping(address => bool) private DEPRECATED_internalWhiteList;

    /// @dev mapping to exclude certain TCO2 contracts by address,
    /// even if the attribute matching would pass
    //slither-disable-next-line constable-states
    mapping(address => bool) private DEPRECATED_internalBlackList;

    /// @dev fees redeem receiver address
    //slither-disable-next-line uninitialized-state,constable-states
    address internal _feeRedeemReceiver;

    //slither-disable-next-line uninitialized-state,constable-states
    uint256 internal _feeRedeemPercentageInBase;

    /// @dev fees redeem burn address
    address internal _feeRedeemBurnAddress;

    /// @dev fees redeem burn percentage with 2 fixed decimals precision
    uint256 internal _feeRedeemBurnPercentageInBase;

    /// @dev repacked smaller variables here so new bools can be added below
    //slither-disable-next-line constable-states
    uint64 private DEPRECATED_minimumVintageStartTime;
    //slither-disable-next-line constable-states
    bool private DEPRECATED_seedMode;
    //slither-disable-next-line constable-states
    bool private DEPRECATED_regionsIsAcceptedMapping;
    //slither-disable-next-line constable-states
    bool private DEPRECATED_standardsIsAcceptedMapping;
    //slither-disable-next-line constable-states
    bool private DEPRECATED_methodologiesIsAcceptedMapping;
}

abstract contract PoolStorageV1_1 {
    /// @notice End users exempted from redeem fees
    mapping(address => bool) public redeemFeeExemptedAddresses;
}

abstract contract PoolStorageV1_2 {
    /// @notice TCO2s exempted from redeem fees
    mapping(address => bool) public redeemFeeExemptedTCO2s;
}

abstract contract PoolStorageV1_3 {
    /// @notice bridge router who has access to the bridgeMint & bridgeBurn functions which
    /// mint/burn pool tokens for cross chain messenges
    address public router;
}

abstract contract PoolStorageV1_4 {
    /// @notice fee percentage in basis points charged for selective
    /// redemptions that also retire the credits in the same transaction
    //slither-disable-next-line uninitialized-state,constable-states
    uint256 internal _feeRedeemRetirePercentageInBase;
    address public filter;
}

abstract contract PoolStorageV1_5 {
    /// @notice module to calculate fees for the pool
    //slither-disable-next-line uninitialized-state,constable-states
    IFeeCalculator public feeCalculator;
    /// @notice Total TCO2 supply in the pool.
    uint256 public totalTCO2Supply;
    /// @notice Project token id to total supply of the project
    /// in the pool.
    mapping(uint256 => uint256) public totalPerProjectTCO2Supply;
}

abstract contract PoolStorage is
    PoolStorageV1,
    PoolStorageV1_1,
    PoolStorageV1_2,
    PoolStorageV1_3,
    PoolStorageV1_4,
    PoolStorageV1_5
{}
