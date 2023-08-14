// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

interface IToucanCarbonOffsetsFactory is IAccessControlUpgradeable {
    function bridgeFeeReceiverAddress()
        external
        view
        returns (address receiver);

    function bridgeFeeBurnAddress() external view returns (address burner);

    function getBridgeFeeAndBurnAmount(uint256 quantity)
        external
        view
        returns (uint256 feeAmount, uint256 burnAmount);

    function allowedBridges(address user) external view returns (bool);

    function owner() external view returns (address);

    function standardRegistry() external returns (string memory);
}
