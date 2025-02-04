// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: LicenseRef-Proprietary
pragma solidity ^0.8.13;

struct Range {
    uint256 start;
    uint256 end;
}

library RangeProtection {
    // Function to add a new range after checking overlap
    function add(
        Range[] storage ranges,
        uint256 start,
        uint256 end
    ) external {
        require(start <= end, 'Invalid range'); // Basic validation

        // If there are no ranges, just add the first one
        if (ranges.length == 0) {
            ranges.push(Range(start, end));
            return;
        }

        (uint256 position, string memory overlapMsg) = findInsertPosition(ranges, start, end);
        require(bytes(overlapMsg).length == 0, overlapMsg);

        // Insert the new range at the correct position
        ranges.push(Range(0, 0)); // Add a blank space at the end to avoid index issues
        for (uint256 i = ranges.length - 1; i > position; i--) {
            ranges[i] = ranges[i - 1];
        }
        ranges[position] = Range(start, end);
    }

    function findInsertPosition(
        Range[] storage ranges,
        uint256 start,
        uint256 end
    ) public view returns (uint256 position, string memory errorMsg) {
        if (ranges.length == 0) {
            return (0, '');
        }

        position = _findInsertPosition(ranges, start);

        if (position > 0 && overlaps(ranges[position - 1], Range(start, end))) {
            return (position, 'Range overlaps with the previous range');
        }

        if (position < ranges.length && overlaps(ranges[position], Range(start, end))) {
            return (position, 'Range overlaps with the next range');
        }

        return (position, '');
    }

    // Binary search function to find the insertion point
    function _findInsertPosition(Range[] storage ranges, uint256 start)
        internal
        view
        returns (uint256)
    {
        uint256 low = 0;
        uint256 high = ranges.length;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (ranges[mid].start < start) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        return low;
    }

    // Helper function to check overlap
    function overlaps(Range memory existingRange, Range memory newRange)
        internal
        pure
        returns (bool)
    {
        return newRange.start <= existingRange.end && newRange.end >= existingRange.start;
    }
}
