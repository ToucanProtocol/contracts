// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './IToucanCarbonOffsetsFactory.sol';

interface IToucanCarbonOffsetsBatchlessFactory {
    function canMint(address _user) external view returns (bool);
}
