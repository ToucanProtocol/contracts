// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import '../ToucanCarbonOffsetsFactory.sol';
import '../CarbonOffsetBatchesStorage.sol';
import '../CarbonOffsetBatches.sol';

////////////////////////////////////////////////////
////////// FOR TESTTING PURPOSES ONLY //////////////
////////////////////////////////////////////////////

abstract contract CarbonOffsetBatchesStorageV2Test is
    CarbonOffsetBatchesStorage
{
    // add one state var
    string public dummyVar;
}

//    ICarbonOffsetBatches,
contract CarbonOffsetBatchesV2Test is
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ProjectUtils,
    CarbonOffsetBatchesStorageV2Test
{
    // string public dummyVar;

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function writeDummyVar(string memory text) external {
        dummyVar = text;
    }

    function readFromStorageV2() external view returns (string memory) {
        return dummyVar;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IAccessControlUpgradeable).interfaceId ||
            ERC721Upgradeable.supportsInterface(interfaceId);
    }
}
