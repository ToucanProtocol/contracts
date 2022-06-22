// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.4 <=0.8.14;

import '../../CarbonOffsetBatchesTypes.sol';

abstract contract CarbonOffsetBatchesStorageV1Test {
    //slither-disable-next-line constable-states
    uint256 public batchTokenCounter;

    mapping(string => bool) public serialNumberExist;
    mapping(string => bool) public URIs;
    mapping(address => bool) public verifiers;

    //slither-disable-next-line constable-states
    string public baseURI;
    //slither-disable-next-line constable-states
    address public contractRegistry;

    struct NFTData {
        uint256 projectVintageTokenId;
        string serialNumber;
        uint256 quantity;
        RetirementStatus status;
        string uri;
        string[] comments;
        address[] commentAuthors;
    }

    mapping(uint256 => NFTData) public nftList;
}
