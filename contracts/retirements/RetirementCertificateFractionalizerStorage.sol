// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

abstract contract RetirementCertificateFractionalizerStorage {
    address public contractRegistry;
    string public beneficiaryString;

    /// @dev mapping from vintage id to the total amount of fractions burnt for that vintage
    mapping(uint256 => uint256) public totalBurntSupply;

    /// @dev mapping from certificate depositor to vintage to a FIFO queue
    /// of retirement event ids
    mapping(address => mapping(uint256 => uint256[]))
        internal _retirementEventIds;
    mapping(uint256 => uint256) public remainingRetirementEventBalance;
}
