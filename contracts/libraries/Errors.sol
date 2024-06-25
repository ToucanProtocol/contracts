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
 *  - COB = CarbonOffsetBatches
 *  - TCO2 = TCO2
 */
library Errors {
    // User is not authorized
    string public constant CP_UNAUTHORIZED = '1';
    // Empty array provided as input
    string public constant CP_EMPTY_ARRAY = '2';
    // Pool is full of TCO2s
    string public constant CP_FULL_POOL = '3';
    // ERC20 is blocklisted in the pool. This error
    // is returned for TCO2s that have been blocklisted
    // like the HFC-23 project.
    string public constant CP_BLOCKLISTED = '4';
    // ERC20 is not allowlisted in the pool
    // This error is returned in case the ERC20 is
    // not a TCO2 in which case it has to be manually
    // allowlisted in order to be allowed in the pool.
    string public constant CP_NOT_ALLOWLISTED = '5';
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
    // ERC20 is not eligible to be pooled
    string public constant CP_NOT_ELIGIBLE = '22';
    // Carbon registry is already supported in COB
    string public constant COB_ALREADY_SUPPORTED = '23';
    // The caller is not granted the VERIFIER_ROLE in COB
    string public constant COB_NOT_VERIFIER_OR_BATCH_OWNER = '24';
    // The caller does not own the provided batch
    string public constant COB_NOT_BATCH_OWNER = '25';
    // The owner of the batch is invalid (not a TCO2 contract)
    string public constant COB_INVALID_BATCH_OWNER = '26';
    // The batch is not in Confirmed status
    string public constant COB_NOT_CONFIRMED = '27';
    // The batch is not in a requested status (DetokenizationRequested or RetirementRequested)
    string public constant COB_NOT_REQUESTED_STATUS = '28';
    // The batch does not exist
    string public constant COB_NOT_EXISTS = '29';
    // The batch has an invalid status based on the action requested
    string public constant COB_INVALID_STATUS = '30';
    // The batch is missing an associated project vintage
    string public constant COB_MISSING_VINTAGE = '31';
    // The serial number in the batch is already approved
    string public constant COB_ALREADY_APPROVED = '32';
    // The batch is not in Pending status
    string public constant COB_NOT_PENDING = '33';
    // The batch is already fractionalized
    string public constant COB_ALREADY_FRACTIONALIZED = '34';
    // The batch is not in Rejected status
    string public constant COB_NOT_REJECTED = '35';
    // The project vintage is already set in the batch
    string public constant COB_VINTAGE_ALREADY_SET = '36';
    // The transfer is not approved
    string public constant COB_TRANSFER_NOT_APPROVED = '37';
    // The COB contract is paused
    string public constant COB_PAUSED_CONTRACT = '38';
    // The caller is invalid
    string public constant COB_INVALID_CALLER = '39';
    // The TCO2 for the batch is not found
    string public constant COB_TCO2_NOT_FOUND = '40';
    // The registry for the provided vintage is not supported
    string public constant COB_REGISTRY_NOT_SUPPORTED = '41';
    // No TCO2 was minted as part of tokenization
    string public constant COB_NO_TCO2_MINTED = '42';
    // Only mints are supported for the batch contract to receive an NFT
    string public constant COB_ONLY_MINTS = '43';
    // New batch status is invalid
    string public constant COB_INVALID_NEW_STATUS = '44';
    // The TCO2 batch amount is invalid
    string public constant TCO2_BATCH_AMT_INVALID = '45';
    // The TCO2 batch amount approval has failed
    string public constant TCO2_APPROVAL_AMT_FAILED = '46';
    // The TCO2 batch not confirmed
    string public constant TCO2_BATCH_NOT_CONFIRMED = '47';
    // The TCO2 batch not whitelisted
    string public constant TCO2_BATCH_NOT_WHITELISTED = '48';
    // The TCO2 is non matching NFT
    string public constant TCO2_NON_MATCHING_NFT = '49';
    // The TCO2 Quantity in batch is higher than total vintages
    string public constant TCO2_QTY_HIGHER = '50';
    // The fee to be charged is too high
    string public constant CP_FEE_TOO_HIGH = '51';
    // The max fee to be paid is invalid
    string public constant CP_INVALID_MAX_FEE = '52';
    // The pool feature is not supported
    string public constant CP_NOT_SUPPORTED = '53';
    // Used for instance to check for sub-tonnage retirement requests
    string public constant TCO2_INVALID_DECIMALS = '54';
    // The TCO2 Quantity in the batch is invalid
    string public constant COB_INVALID_QUANTITY = '55';
    // Splitting is required on detokenization/retirement finalization, but 2 new serial numbers
    // were not provided
    string public constant TCO2_MISSING_SERIALS = '56';
    // The score set for the ERC-1155 token in the pool is invalid
    string public constant INVALID_ERC1155_SCORE = '57';
    // The score of the ERC-1155 token in the pool is not set
    string public constant EMPTY_ERC155_SCORE = '58';
    // The underlying decimals are too high for the pool
    string public constant UNDERLYING_DECIMALS_TOO_HIGH = '59';
    // The provided supply cap is invalid and should match the underlying token decimals
    // eg., for an ERC-1155 token whose smallest denomination is tonnes, the pool supply
    // cap should not include decimals of lower fidelity than tonnes.
    string public constant INVALID_SUPPLY_CAP = '60';
}
