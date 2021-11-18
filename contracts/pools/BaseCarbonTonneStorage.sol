// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity ^0.8.0;

/// @dev Storage for UUPS Proxy upgradable BaseCarbonTonne
contract BaseCarbonTonneStorage {
    uint256 public supplyCap;
    mapping(address => uint256) public tokenBalances;
    address public contractRegistry;

    uint64 public minimumVintageStartTime;

    /// @dev Mappings for attributes that can be included or excluded
    /// if set to `false`, attribute-values are blacklisted/rejected
    /// if set to `true`, attribute-values are whitelisted/accepted
    bool public regionsIsAcceptedMapping;
    mapping(string => bool) public regions;

    bool public standardsIsAcceptedMapping;
    mapping(string => bool) public standards;

    bool public methodologiesIsAcceptedMapping;
    mapping(string => bool) public methodologies;

    /// @dev mapping to whitelist external non-TCO2 contracts by address
    mapping(address => bool) public externalWhiteList;

    /// @dev mapping to include certain TCO2 contracts by address,
    /// overriding attribute matching checks
    mapping(address => bool) public internalWhiteList;

    /// @dev mapping to exclude certain TCO2 contracts by address,
    /// even if the attribute matching would pass
    mapping(address => bool) public internalBlackList;

    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
}
