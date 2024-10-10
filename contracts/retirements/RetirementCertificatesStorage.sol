// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {CertificateData, RetirementEvent} from './interfaces/IRetirementCertificates.sol';

abstract contract RetirementCertificatesStorageV1 {
    /// @dev id that tracks retirement events
    uint256 public retireEventCounter;

    /// @dev maps the retireEventCounter to the RetirementEvent data, exposed
    /// publicly through the `retirements(uint256)` function.
    mapping(uint256 => RetirementEvent) internal _retirements;

    /// @dev mapping that helps ensure retirement events are not claimed multiple times
    mapping(uint256 => bool) public claimedEvents;

    /// @dev List all the events belonging to user (maybe this could be better inferred via a subgraph)
    mapping(address => uint256[]) eventsOfUser;

    string public baseURI;
    address public contractRegistry;
    uint256 internal _tokenIds;

    /// @dev Mapping of tokenId to CertificateData, exposed publicly
    /// through the `certificates(uint256)` function.
    mapping(uint256 => CertificateData) internal _certificates;

    uint256 public minValidRetirementAmount;
}

/// @dev Kept separate from RetirementCertificatesStorageV1 to
/// add ReentrancyGuardUpgradeable in between.
abstract contract RetirementCertificatesStorage {

}
