// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {SliceData} from '../retirements/RetirementCertificateSlicesTypes.sol';

interface IRetirementCertificateSlices {
    function mintSlice(address caller, SliceData calldata sliceData)
        external
        returns (uint256);
}
