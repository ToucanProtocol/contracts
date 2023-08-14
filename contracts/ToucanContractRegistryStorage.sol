// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

abstract contract ToucanContractRegistryStorageLegacy {
    address internal _carbonOffsetBatchesAddress;
    address internal _carbonProjectsAddress;
    address internal _carbonProjectVintagesAddress;
    //slither-disable-next-line uninitialized-state,constable-states
    address internal DEPRECATED_toucanCarbonOffsetsFactoryAddress;
    address internal _retirementCertificatesAddress;
    mapping(address => bool) public projectVintageERC20Registry;
}

abstract contract ToucanContractRegistryStorageV1 {
    /// @notice map of standard registries to tco2 factory addresses
    mapping(string => address) public toucanCarbonOffsetFactories;
    /// @dev make it easy to get the supported standard registries
    string[] internal standardRegistries;
}

abstract contract ToucanContractRegistryStorageV2 {
    address internal _toucanCarbonOffsetsEscrowAddress;
}

abstract contract ToucanContractRegistryStorage is
    ToucanContractRegistryStorageV1,
    ToucanContractRegistryStorageV2
{}
