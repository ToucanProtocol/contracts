// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

abstract contract PoolStorageV1 {
    uint256 public supplyCap;
    mapping(address => uint256) public tokenBalances;
    address public contractRegistry;

    /// @notice array used to read from when redeeming TCO2s automatically
    address[] public scoredTCO2s;

    /// @dev Mappings for attributes that can be included or excluded
    /// if set to `false`, attribute-values are blacklisted/rejected
    /// if set to `true`, attribute-values are whitelisted/accepted
    mapping(string => bool) public regions;
    mapping(string => bool) public standards;
    mapping(string => bool) public methodologies;

    /// @dev mapping to whitelist external non-TCO2 contracts by address
    mapping(address => bool) public externalWhiteList;

    /// @dev mapping to include certain TCO2 contracts by address,
    /// overriding attribute matching checks
    mapping(address => bool) public internalWhiteList;

    /// @dev mapping to exclude certain TCO2 contracts by address,
    /// even if the attribute matching would pass
    mapping(address => bool) public internalBlackList;

    /// @dev fees redeem receiver address
    address public feeRedeemReceiver;

    uint256 public feeRedeemPercentageInBase;

    /// @dev fees redeem burn address
    address public feeRedeemBurnAddress;

    /// @dev fees redeem burn percentage with 2 fixed decimals precision
    uint256 public feeRedeemBurnPercentageInBase;

    /// @dev repacked smaller variables here so new bools can be added below
    uint64 public minimumVintageStartTime;
    //slither-disable-next-line constable-states
    bool public seedMode;
    bool public regionsIsAcceptedMapping;
    bool public standardsIsAcceptedMapping;
    bool public methodologiesIsAcceptedMapping;
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

abstract contract PoolStorage is
    PoolStorageV1,
    PoolStorageV1_1,
    PoolStorageV1_2,
    PoolStorageV1_3
{}
