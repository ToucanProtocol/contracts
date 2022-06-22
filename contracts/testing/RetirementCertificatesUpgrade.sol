// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../RetirementCertificates.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

contract RetirementCertificatesV2Test is RetirementCertificates {
    //slither-disable-next-line constable-states
    uint256 public num;
    //slither-disable-next-line constable-states
    string public dummyVar;

    function version() external pure virtual override returns (string memory) {
        return 'V2';
    }

    /// @dev dummy function that overrides
}
