// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../ToucanCarbonOffsets.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

contract ToucanCarbonOffsetsV2Test is ToucanCarbonOffsets {
    // add one state var
    string public dummyVar;

    function writeDummyVar(string memory text) external {
        dummyVar = text;
    }

    function readFromStorageV2() external view returns (string memory) {
        return dummyVar;
    }

    function version() external pure virtual override returns (string memory) {
        return 'V2';
    }
}
