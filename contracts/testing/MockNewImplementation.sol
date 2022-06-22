// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <=0.8.14;

/// @dev mock upgrade contract that should fail UUPS upgrade test
/// This is due to the fact that is does not inherit from UUPSUpgradeable
contract MockV2UpgradeTest {
    function whatsMyName() external pure returns (string memory) {
        return 'MockV2UpgradeTest';
    }
}
