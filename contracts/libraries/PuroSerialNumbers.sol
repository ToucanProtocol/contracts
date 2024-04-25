// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Strings} from './Strings.sol';

struct SerialNumber {
    // Fields relevant to serial numbers prior to the
    // Puro API migration.
    string startSerial;
    string endSerial;
    string serialType;
    // Fields relevant to serial numbers after the
    // Puro API migration.
    string issuanceId;
    // Fields relevant to serial numbers both before and
    // after the Puro API migration.
    uint256 rangeStart;
    uint256 rangeEnd;
}

library PuroSerialNumbers {
    using Strings for string;
    using Strings for uint256;

    // The size info of the serials before the migration to the new Puro API.
    // Example: 643002406555908610000000140219-643002406555908610000000140220
    // We need to maintain the serial numbers that were added on-chain
    // before the migration until we can update serials directly on-chain (LILA-7025).
    uint256 internal constant TYPE_SIZE = 18;
    uint256 internal constant NUMBER_SIZE = 12;
    uint256 internal constant SERIAL_SIZE = TYPE_SIZE * 2 + NUMBER_SIZE * 2 + 1;
    // The info of the serials that are submitted on-chain after the Puro API migration.
    // Example: 40980b1a-cff7-4c78-9cc5-a3a2f18c7e0d_1000-1001
    uint256 internal constant ISSUANCE_ID_SIZE = 36;

    /// @notice Parse a serial number range
    /// @param serialNumber The serial number string to parse
    /// @return The parsed serial number
    function parseSerialNumber(string memory serialNumber)
        internal
        pure
        returns (SerialNumber memory)
    {
        if (bytes(serialNumber).length == SERIAL_SIZE) {
            return parseSerialNumberV1(serialNumber);
        }
        return parseSerialNumberV2(serialNumber);
    }

    /// @notice Parse a serial number range that was created on-chain before the
    /// Puro API migration.
    /// @param serialNumber The serial number string to parse
    /// @return The parsed serial number
    function parseSerialNumberV1(string memory serialNumber)
        internal
        pure
        returns (SerialNumber memory)
    {
        if (serialNumber.count('-') != 1) {
            revert('v1: incorrect delimiter count');
        }

        // Split the serial number range into start and end.
        (string memory startSerial, string memory endSerial) = serialNumber
            .split('-');

        // Get the part of the serial that is related to the type
        // of the batch and validate that it is the same for both
        // serials.
        string memory startType = startSerial.slice(0, TYPE_SIZE);
        string memory endType = endSerial.slice(0, TYPE_SIZE);
        if (!startType.equals(endType)) {
            revert('Type mismatch');
        }

        // Get the part of the serial that is related to the amount,
        // convert to integer, and ensure start is less than end.
        uint256 rangeStart = startSerial
            .slice(TYPE_SIZE + 1, TYPE_SIZE + NUMBER_SIZE)
            .toInteger();
        uint256 rangeEnd = endSerial
            .slice(TYPE_SIZE + 1, TYPE_SIZE + NUMBER_SIZE)
            .toInteger();
        if (rangeStart > rangeEnd) {
            revert('Invalid range');
        }

        return
            SerialNumber({
                issuanceId: '',
                startSerial: startSerial,
                endSerial: endSerial,
                serialType: startType,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            });
    }

    /// @notice Parse a serial number range that was created on-chain after the
    /// Puro API migration.
    /// @param serialNumber The serial number string to parse
    /// @return The parsed serial number
    function parseSerialNumberV2(string memory serialNumber)
        internal
        pure
        returns (SerialNumber memory)
    {
        if (serialNumber.count('_') != 1) {
            revert('v2: incorrect delimiter count');
        }

        // Split the serial number range into issuance id and the
        // actual range.
        (string memory issuanceId, string memory range) = serialNumber.split(
            '_'
        );

        // Validate the issuance id.
        if (!isValidIssuanceId(issuanceId)) {
            revert('Invalid issuance id');
        }

        // Validate the range.
        if (range.count('-') != 1) {
            revert('Incorrect delimiter count in range');
        }
        (string memory startString, string memory endString) = range.split('-');
        uint256 rangeStart = startString.toInteger();
        uint256 rangeEnd = endString.toInteger();
        if (rangeStart > rangeEnd) {
            revert('Invalid range');
        }

        return
            SerialNumber({
                startSerial: '',
                endSerial: '',
                serialType: '',
                issuanceId: issuanceId,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            });
    }

    function isValidIssuanceId(string memory issuanceId)
        internal
        pure
        returns (bool)
    {
        // Basic UUID validation, far from complete.
        // Probably not worth it to have more than this
        // on-chain but we could definitely extend in the
        // future as long as we don't deploy on L1.
        return
            bytes(issuanceId).length == ISSUANCE_ID_SIZE &&
            issuanceId.count('-') == 4;
    }

    /// @notice Split a serial number range into two parts based on
    /// the given amount.
    /// @param serialNumber The serial number to split
    /// @param amount The amount to split by
    /// @return balancingSerialNumber remainingSerialNumber The serial
    /// numbers split from the original serial number.
    function splitSerialNumber(SerialNumber memory serialNumber, uint256 amount)
        internal
        pure
        returns (
            string memory balancingSerialNumber,
            string memory remainingSerialNumber
        )
    {
        if (bytes(serialNumber.issuanceId).length != 0) {
            return splitSerialNumberV2(serialNumber, amount);
        }
        return splitSerialNumberV1(serialNumber, amount);
    }

    /// @notice Split a serial number range into two parts based on
    /// the given amount. This is valid for splitting serial numbers
    /// that were created on-chain before the Puro API migration.
    /// @param serialNumber The serial number to split
    /// @param amount The amount to split by
    /// @return balancingSerialNumber remainingSerialNumber The serial
    /// numbers split from the original serial number.
    function splitSerialNumberV1(
        SerialNumber memory serialNumber,
        uint256 amount
    )
        internal
        pure
        returns (
            string memory balancingSerialNumber,
            string memory remainingSerialNumber
        )
    {
        if (amount == 0) {
            revert('Empty amount');
        }
        if (amount >= serialNumber.rangeEnd - serialNumber.rangeStart + 1) {
            revert('Cannot split');
        }

        // Determine intermediate serial numbers
        uint256 balancingEndNum = serialNumber.rangeStart + amount - 1;
        uint256 remainingStartNum = balancingEndNum + 1;

        // Pad amounts
        string memory paddedBalancingEnd = balancingEndNum.toString().pad(
            NUMBER_SIZE,
            '0'
        );
        string memory paddedRemainingStart = remainingStartNum.toString().pad(
            NUMBER_SIZE,
            '0'
        );
        string memory balancingEnd = string.concat(
            serialNumber.serialType,
            paddedBalancingEnd
        );
        string memory remainingStart = string.concat(
            serialNumber.serialType,
            paddedRemainingStart
        );

        // Create new serials
        return (
            string.concat(
                string.concat(serialNumber.startSerial, '-'),
                balancingEnd
            ),
            string.concat(
                string.concat(remainingStart, '-'),
                serialNumber.endSerial
            )
        );
    }

    /// @notice Split a serial number range into two parts based on
    /// the given amount. This is valid for splitting serial numbers
    /// that were created on-chain after the Puro API migration.
    /// @param serialNumber The serial number to split
    /// @param amount The amount to split by
    /// @return balancingSerialNumber remainingSerialNumber The serial
    /// numbers split from the original serial number.
    function splitSerialNumberV2(
        SerialNumber memory serialNumber,
        uint256 amount
    )
        internal
        pure
        returns (
            string memory balancingSerialNumber,
            string memory remainingSerialNumber
        )
    {
        if (amount == 0) {
            revert('Empty amount');
        }
        if (amount >= serialNumber.rangeEnd - serialNumber.rangeStart + 1) {
            revert('Cannot split');
        }

        // Determine intermediate serial numbers
        uint256 balancingEndNum = serialNumber.rangeStart + amount - 1;
        uint256 remainingStartNum = balancingEndNum + 1;

        // Create new serials
        return (
            string.concat(
                serialNumber.issuanceId,
                '_',
                serialNumber.rangeStart.toString(),
                '-',
                balancingEndNum.toString()
            ),
            string.concat(
                serialNumber.issuanceId,
                '_',
                remainingStartNum.toString(),
                '-',
                serialNumber.rangeEnd.toString()
            )
        );
    }
}
