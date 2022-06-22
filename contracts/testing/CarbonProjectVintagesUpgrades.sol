// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../CarbonProjectVintages.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

contract CarbonProjectVintagesV2Test is CarbonProjectVintages {
    struct Data {
        bool var1;
        uint256 var2;
    }
    mapping(uint256 => Data) public dataList;
    uint256 public num;

    function addData() external {
        dataList[1].var1 = true;
        dataList[1].var2 = 1337;
        num = 10;
    }

    function version() external pure returns (string memory) {
        return 'V2';
    }
}
