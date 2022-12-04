// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth

pragma solidity 0.8.14;

/// @dev V1 Storage contract for ToucanCarbonOffsetsFactory v.1.0
abstract contract ToucanCarbonOffsetsFactoryStorageV1 {
    address public contractRegistry;
    address[] public deployedContracts;
    mapping(uint256 => address) public pvIdtoERC20;
}

/// @dev V2 Storage contract for ToucanCarbonOffsetsFactory v.1.1
abstract contract ToucanCarbonOffsetsFactoryStorageV2 {
    address public beacon;

    address public bridgeFeeReceiver;
    uint256 public bridgeFeePercentageInBase;
    address public bridgeFeeBurnAddress;
    uint256 public bridgeFeeBurnPercentageInBase;
    uint256 public totalRetired;
}

/// @dev V3 Storage contract for ToucanCarbonOffsetsFactory v.1.2
abstract contract ToucanCarbonOffsetsFactoryStorageV3 {
    /// @notice meant to be used only for cross-chain bridging
    mapping(address => bool) public allowedBridges;
}

/// @dev Main storage contract inheriting new versions
/// @dev V1 is not inherited as it was inherited in the main contract
abstract contract ToucanCarbonOffsetsFactoryStorage is
    ToucanCarbonOffsetsFactoryStorageV2,
    ToucanCarbonOffsetsFactoryStorageV3
{
    /// @dev add a storage gap so future upgrades can introduce new variables
    /// This is also allows for other dependencies to be inherited after this one
    uint256[44] private __gap;
}
