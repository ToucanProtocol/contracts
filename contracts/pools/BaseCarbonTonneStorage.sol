// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

/// @dev Storage for UUPS Proxy upgradable BaseCarbonTonne
abstract contract BaseCarbonTonneStorageV1 {
    /// @notice The supply cap is used as a measure to guard deposits
    /// in the pool. It is meant to minimize the impact a potential
    /// compromise in the source registry (eg. Verra) can have to the pool.
    uint256 public supplyCap;
    //slither-disable-next-line constable-states
    mapping(address => uint256) private DEPRECATED_tokenBalances;
    //slither-disable-next-line constable-states
    address private DEPRECATED_contractRegistry;

    //slither-disable-next-line constable-states
    uint64 private DEPRECATED_minimumVintageStartTime;

    /// @dev Mappings for attributes that can be included or excluded
    /// if set to `false`, attribute-values are blacklisted/rejected
    /// if set to `true`, attribute-values are whitelisted/accepted
    //slither-disable-next-line constable-states
    bool private DEPRECATED_regionsIsAcceptedMapping;
    //slither-disable-next-line constable-states
    mapping(string => bool) private DEPRECATED_regions;

    //slither-disable-next-line constable-states
    bool private DEPRECATED_standardsIsAcceptedMapping;
    //slither-disable-next-line constable-states
    mapping(string => bool) private DEPRECATED_standards;

    //slither-disable-next-line constable-states
    bool private DEPRECATED_methodologiesIsAcceptedMapping;
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
}

abstract contract BaseCarbonTonneStorageV1_1 {
    /// @dev fees redeem receiver address
    address public feeRedeemReceiver;

    uint256 public feeRedeemPercentageInBase;

    /// @dev fees redeem burn address
    address public feeRedeemBurnAddress;

    /// @dev fees redeem burn percentage with 2 fixed decimals precision
    uint256 public feeRedeemBurnPercentageInBase;
}

abstract contract BaseCarbonTonneStorageV1_2 {
    /// @notice End users exempted from redeem fees
    mapping(address => bool) public redeemFeeExemptedAddresses;

    /// @notice array used to read from when redeeming TCO2s automatically
    address[] public scoredTCO2s;
}

abstract contract BaseCarbonTonneStorageV1_3 {
    /// @notice TCO2s exempted from redeem fees
    mapping(address => bool) public redeemFeeExemptedTCO2s;
}

abstract contract BaseCarbonTonneStorageV1_4 {
    /// @notice bridge router who has access to the bridgeMint & bridgeBurn functions which
    /// mint/burn pool tokens for cross chain messenges
    address public router;
}

abstract contract BaseCarbonTonneStorageV1_5 {
    /// @notice fee percentage in basis points charged for selective
    /// redemptions that also retire the credits in the same transaction
    uint256 public feeRedeemRetirePercentageInBase;
    address public filter;
}

abstract contract BaseCarbonTonneStorage is
    BaseCarbonTonneStorageV1,
    BaseCarbonTonneStorageV1_1,
    BaseCarbonTonneStorageV1_2,
    BaseCarbonTonneStorageV1_3,
    BaseCarbonTonneStorageV1_4,
    BaseCarbonTonneStorageV1_5
{}
