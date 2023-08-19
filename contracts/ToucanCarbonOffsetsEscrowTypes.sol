// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

struct DetokenizationRequest {
    address user;
    uint256 amount;
    RequestStatus status;
    // The request may optionally be associated with one or more batches.
    uint256[] batchTokenIds;
}

enum RequestStatus {
    Pending,
    Finalized,
    Reverted
}
