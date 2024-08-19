// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '../retirements/RetirementCertificateSlicesTypes.sol';

interface IRetirementCertificateSlicer {
    function mintSlice(SliceRequestData calldata params)
        external
        returns (uint256 sliceTokenId);

    function mintSliceFrom(address from, SliceRequestData calldata params)
        external
        returns (uint256 sliceTokenId);
}
