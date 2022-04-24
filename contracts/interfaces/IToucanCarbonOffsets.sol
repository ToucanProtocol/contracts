// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity ^0.8.0;

import '../CarbonProjectVintageTypes.sol';
import '../CarbonProjectTypes.sol';

interface IToucanCarbonOffsets {
    function getAttributes()
        external
        view
        returns (ProjectData memory, VintageData memory);
}
