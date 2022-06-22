// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '../interfaces/IToucanContractRegistry.sol';
import '../interfaces/ICarbonProjectVintages.sol';

contract ProjectVintageUtils {
    function checkProjectVintageTokenExists(
        address contractRegistry,
        uint256 tokenId
    ) internal virtual {
        address c = IToucanContractRegistry(contractRegistry)
            .carbonProjectVintagesAddress();
        require(
            ICarbonProjectVintages(c).exists(tokenId),
            'Carbon project vintage does not yet exist'
        );
    }
}
