// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../CarbonProjects.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

contract CarbonProjectsV2Test is CarbonProjects {
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

////////////////////////////////////

contract CarbonProjectsV3Test is CarbonProjects {
    struct Data {
        bool var1;
        uint256 var2;
        string text;
    }
    mapping(uint256 => Data) public dataList;

    function changeData() external {
        dataList[1].var1 = false;
        dataList[1].var2 = 1;
    }

    function addText() external {
        dataList[1].text = 'Hello';
    }

    function readData()
        external
        view
        returns (
            bool,
            uint256,
            string memory,
            uint256
        )
    {
        return (dataList[1].var1, dataList[1].var2, dataList[1].text, 0);
    }

    function version() external pure returns (string memory) {
        return 'V3';
    }
}

abstract contract CarbonProjectsStorageV2Test is CarbonProjectsStorage {
    string public dummyVar;
}

// Test for upgrade according to data separation pattern
contract CarbonProjectsV4Test is
    CarbonProjectsV3Test,
    CarbonProjectsStorageV2Test
{
    function writeDummyVar(string memory text) external {
        dummyVar = text;
    }

    function readFromStorageV2() external view returns (string memory) {
        return dummyVar;
    }
}
