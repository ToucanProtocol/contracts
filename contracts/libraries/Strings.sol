// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

library Strings {
    function equals(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return
            (bytes(a).length == bytes(b).length) &&
            (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
