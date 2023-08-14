// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '../ToucanCarbonOffsetsEscrowTypes.sol';

interface IToucanCarbonOffsetsEscrow {
    function createDetokenizationRequest(
        address user,
        uint256 amount,
        uint256[] calldata batchTokenIds
    ) external returns (uint256);

    function finalizeDetokenizationRequest(uint256 requestId) external;

    function revertRequest(uint256 requestId) external;

    function requests(uint256 requestId) external view returns (Request memory);
}
