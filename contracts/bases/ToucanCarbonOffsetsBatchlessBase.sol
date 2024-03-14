// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsBase.sol';

/// @notice
contract ToucanCarbonOffsetsBatchlessBase is ToucanCarbonOffsetsBase {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event Tokenized(
        string indexed identifier,
        uint256 amount,
        address indexed beneficiary
    );

    // ----------------------------------------
    //      Functions
    // ----------------------------------------

    function tokenize(
        string calldata _identifier,
        uint256 _amount,
        uint256 _deadline,
        address _beneficiary
    ) external virtual whenNotPaused onlyWithRole(TOKENIZER_ROLE) {
        require(block.timestamp < _deadline, 'Deadline has passed');
        _mint(_beneficiary, _amount);
        emit Tokenized(_identifier, _amount, _beneficiary);
    }
}
