// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

/**
 * @title Errors library
 * @notice Defines the error messages emitted by the different contracts of the Toucan protocol
 * @dev Inspired by the AAVE error library:
 * https://github.com/aave/protocol-v2/blob/5df59ec74a0c635d877dc1c5ee4a165d41488352/contracts/protocol/libraries/helpers/Errors.sol
 * Error messages prefix glossary:
 *  - CP = CarbonPool
 */
library Errors {
    // User is not authorized
    string public constant CP_UNAUTHORIZED = '1';
    // Empty array provided as input
    string public constant CP_EMPTY_ARRAY = '2';
    // Pool is full of TCO2s
    string public constant CP_FULL_POOL = '3';
    // ERC20 is blacklisted in the pool. This error
    // is returned for TCO2s that have been blacklisted
    // like the HFC-23 project.
    string public constant CP_BLACKLISTED = '4';
    // ERC20 is not whitelisted in the pool
    // This error is returned in case the ERC20 is
    // not a TCO2 in which case it has to be manually
    // whitelisted in order to be allowed in the pool.
    string public constant CP_NOT_WHITELISTED = '5';
    // Vintage start time of a TCO2 is too old
    string public constant CP_START_TIME_TOO_OLD = '6';
    string public constant CP_REGION_NOT_ACCEPTED = '7';
    string public constant CP_STANDARD_NOT_ACCEPTED = '8';
    string public constant CP_METHODOLOGY_NOT_ACCEPTED = '9';
    // Provided fee is invalid, not in a basis points format: [0,10000)
    string public constant CP_INVALID_FEE = '10';
    // Provided address needs to be non-zero
    string public constant CP_EMPTY_ADDRESS = '11';
    // Validation check to ensure array lengths match
    string public constant CP_LENGTH_MISMATCH = '12';
    // TCO2 not exempted from redeem fees
    string public constant CP_NOT_EXEMPTED = '13';
    // A contract has been paused
    string public constant CP_PAUSED_CONTRACT = '14';
    // Redemption has leftover unredeemed value
    string public constant CP_NON_ZERO_REMAINING = '15';
    // Redemption exceeds deposited TCO2 supply
    string public constant CP_EXCEEDS_TCO2_SUPPLY = '16';
    // User must be a router
    string public constant CP_ONLY_ROUTER = '17';
    // User must be the owner
    string public constant CP_ONLY_OWNER = '18';
    // Zero destination address is invalid for pool token transfers
    string public constant CP_INVALID_DESTINATION_ZERO = '19';
    // Self destination address is invalid for pool token transfers
    string public constant CP_INVALID_DESTINATION_SELF = '20';
    // Zero amount provided as an input (eg., in redemptions) in invalid
    string public constant CP_ZERO_AMOUNT = '21';
}
