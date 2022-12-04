// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

interface IBridgeableToken {
    function bridgeMint(address _account, uint256 _amount) external;

    function bridgeBurn(address _account, uint256 _amount) external;
}
