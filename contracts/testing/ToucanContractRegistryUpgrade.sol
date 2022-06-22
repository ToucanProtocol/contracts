// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../ToucanContractRegistry.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

contract ToucanContractRegistryV2Test is ToucanContractRegistry {
    //slither-disable-next-line constable-states
    address public myNewContractAddress;
    //slither-disable-next-line constable-states
    address public myNewContractAddress2;

    function version() external pure returns (string memory) {
        return 'V2';
    }
}
