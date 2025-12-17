// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import {BatchStatus} from './CarbonOffsetBatchesTypes.sol';

/// @dev Separate storage contract to improve upgrade safety
abstract contract CarbonOffsetBatchesStorageV1 {
    uint256 public batchTokenCounter;
    /// @custom:oz-upgrades-renamed-from serialNumberExist
    mapping(string => bool) public serialNumberApproved;
    mapping(string => bool) private DEPRECATED_URIs;
    mapping(address => bool) private DEPRECATED_VERIFIERS;

    string internal baseURI;
    address public contractRegistry;

    struct NFTData {
        uint256 projectVintageTokenId;
        string serialNumber;
        // Quantity is denominated in tonnes
        uint256 quantity;
        BatchStatus status;
        string uri;
        string[] comments;
        address[] commentAuthors;
    }

    mapping(uint256 => NFTData) public nftList;
}

abstract contract CarbonOffsetBatchesStorageV2 {
    mapping(string => bool) internal supportedRegistries;
}

abstract contract CarbonOffsetBatchesStorage is
    CarbonOffsetBatchesStorageV1,
    CarbonOffsetBatchesStorageV2
{}
