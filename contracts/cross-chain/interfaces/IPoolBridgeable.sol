// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

interface IPoolBridgeable {
    function completeTCO2Bridging(
        address[] memory tco2s,
        uint256[] memory amount
    ) external;
}
