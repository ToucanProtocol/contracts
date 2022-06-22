// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../pools/BaseCarbonTonne.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

contract BaseCarbonTonneDummyTest is BaseCarbonTonne {
    //slither-disable-next-line constable-states
    uint256 public num;
    //slither-disable-next-line constable-states
    string public dummyVar;

    function version() external pure override returns (string memory) {
        return 'V2';
    }

    /// @dev dummy function that overrides
    function deposit(
        address erc20Addr,
        uint256 /*amount*/
    ) external virtual override {
        require(checkEligible(erc20Addr), 'Token rejected');
    }
}
