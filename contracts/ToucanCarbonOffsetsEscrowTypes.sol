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
    uint256 projectVintageTokenId;
}

struct RetirementRequest {
    address user;
    uint256 amount;
    RequestStatus status;
    // The request may optionally be associated with one or more batches.
    // This may need to be limited to one batch for registries which don't
    // support atomic retirement of multiple batches in one go, since
    // retiring one batch at a time might create a situation where our
    // RetirementRequest is only partially fulfilled, and then we would be
    // stuck with no way forwards and no way to roll back.
    uint256[] batchTokenIds;
    // Optional
    string retiringEntityString;
    // Optional
    address beneficiary;
    // Optional
    string beneficiaryString;
    // Optional
    string retirementMessage;
    // Optional
    string beneficiaryLocation;
    // Optional
    string consumptionCountryCode;
    // Optional
    uint256 consumptionPeriodStart;
    // Optional
    uint256 consumptionPeriodEnd;
    uint256 projectVintageTokenId;
}

enum RequestStatus {
    Pending,
    Finalized,
    Reverted
}
