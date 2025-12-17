// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';

library Strings {
    /// @notice Compare two strings
    /// @param a The string to compare
    /// @param b The string to compare to
    /// @return True if the strings are equal, false otherwise
    function equals(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return StringsUpgradeable.equal(a, b);
    }

    /// @notice Convert a string to an integer
    /// @param numString The string to convert
    /// @return The integer value of the string
    function toInteger(string memory numString)
        internal
        pure
        returns (uint256)
    {
        uint256 val = 0;
        bytes memory stringBytes = bytes(numString);
        uint256 stringBytesLen = stringBytes.length;
        for (uint256 i = 0; i < stringBytesLen; ++i) {
            uint256 exp = stringBytesLen - i;
            bytes1 ival = stringBytes[i];
            uint8 uval = uint8(ival);
            uint256 jval = uval - uint256(0x30);

            val += (uint256(jval) * (10**(exp - 1)));
        }
        return val;
    }

    /// @notice Convert an integer to a string
    /// @param value The integer to convert
    /// @return The string value of the integer
    function toString(uint256 value) internal pure returns (string memory) {
        return StringsUpgradeable.toString(value);
    }

    /// @notice Get a substring of a string
    /// @param text The string to get a substring from
    /// @param begin The start index of the substring
    /// @param end The end index of the substring
    /// @return The substring
    function slice(
        string memory text,
        uint256 begin,
        uint256 end
    ) internal pure returns (string memory) {
        uint256 length = end - begin;
        bytes memory a = new bytes(length);
        for (uint256 i = 0; i < length; ++i) {
            a[i] = bytes(text)[i + begin];
        }
        return string(a);
    }

    /// @notice Pad a string with a character
    /// @param text The string to pad
    /// @param length The length to pad to
    /// @param padChar The character to pad with
    /// @return The padded string
    function pad(
        string memory text,
        uint256 length,
        string memory padChar
    ) internal pure returns (string memory) {
        uint256 textLen = bytes(text).length;
        require(bytes(padChar).length == 1, 'Invalid padChar length');
        require(length >= textLen, 'Invalid text length');

        for (uint256 i = textLen; i < length; ++i) {
            text = string.concat(padChar, text);
        }

        return text;
    }

    /// @notice Count the occurrences of a character in a string
    /// @param text The string to count occurrences of char in
    /// @param char The character to count
    /// @return nums The number of occurrences
    function count(string memory text, string memory char)
        internal
        pure
        returns (uint256 nums)
    {
        require(bytes(char).length == 1, 'Invalid char length');
        bytes1 c = bytes(char)[0];

        uint256 textLen = bytes(text).length;
        for (uint256 i = 0; i < textLen; ++i) {
            if (bytes(text)[i] == c) {
                ++nums;
            }
        }
    }

    /// @notice Split a string into two parts. The first occurrence of the delimiter
    /// is used to split the string into first and last.
    /// @param text The string to split
    /// @param delimiter The character to split on
    /// @return first last The two parts of the string
    function split(string memory text, string memory delimiter)
        internal
        pure
        returns (string memory first, string memory last)
    {
        require(bytes(delimiter).length == 1, 'Invalid delimiter length');
        bytes1 d = bytes(delimiter)[0];

        uint256 textLen = bytes(text).length;
        for (uint256 i = 0; i < textLen; ++i) {
            if (bytes(text)[i] == d) {
                first = slice(text, 0, i);
                last = slice(text, i + 1, textLen);
                return (first, last);
            }
        }
    }
}
