// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsEscrowTypes.sol';

abstract contract ToucanCarbonOffsetsEscrowStorageV1 {
    address public contractRegistry;
    // Monotonically increasing request id counter
    uint256 public detokenizationRequestIdCounter;
    // Request id to request data
    mapping(uint256 => DetokenizationRequest) internal _detokenizationRequests;
    // Retirement request id counter
    uint256 public retirementRequestIdCounter;
    // Request id to request data
    mapping(uint256 => RetirementRequest) internal _retirementRequests;
}

abstract contract ToucanCarbonOffsetsEscrowStorage is
    ToucanCarbonOffsetsEscrowStorageV1
{}
