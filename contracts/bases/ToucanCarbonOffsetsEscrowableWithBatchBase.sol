// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsWithBatchBase.sol';
import {Errors} from '../libraries/Errors.sol';

/// @notice Base contract that can be reused between different TCO2
/// implementations that need to work with batch NFTs
abstract contract ToucanCarbonOffsetsEscrowableWithBatchBase is
    IERC721Receiver,
    ToucanCarbonOffsetsWithBatchBase
{
    // ----------------------------------------
    //       Events
    // ----------------------------------------

    event DetokenizationRequested(
        address indexed user,
        uint256 amount,
        uint256 indexed requestId,
        uint256[] batchIds
    );
    event DetokenizationReverted(uint256 indexed requestId);
    event DetokenizationFinalized(uint256 indexed requestId);

    event RetirementRequested(
        address indexed user,
        uint256 indexed requestId,
        CreateRetirementRequestParams params
    );
    event RetirementReverted(uint256 indexed requestId);
    event RetirementFinalized(uint256 indexed requestId);

    // ----------------------------------------
    //       Modifiers
    // ----------------------------------------

    modifier nonFractional(uint256 amount) {
        uint256 maxPrecision = 10**standardRegistryDecimals();
        require(
            amount == (amount / maxPrecision) * maxPrecision,
            Errors.TCO2_INVALID_DECIMALS
        );

        _;
    }

    // ----------------------------------------
    //       Admin functions
    // ----------------------------------------

    /// @notice Finalize a detokenization request by burning its amount of TCO2. In case the amount requested is
    /// smaller than the total amount of TCO2 in the batches, the last batch is split into two new batches, one that
    /// balances the total to be the amount requested and the other with the remaining amount.
    /// @dev Callable only by a detokenizer.
    /// @param requestId The id of the request to finalize.
    /// @param splitBalancingSerialNumber The serial number of the new batch that balances the total amount to be the
    /// amount requested. This batch will be detokenized with the rest of the batches. Ignored if no splitting is
    /// required.
    /// @param splitRemainingSerialNumber The serial number of the new batch with the remaining amount. This batch will
    /// not be detokenized and will be in Confirmed status. Ignored if no splitting is required.
    function finalizeDetokenization(
        uint256 requestId,
        string calldata splitBalancingSerialNumber,
        string calldata splitRemainingSerialNumber
    ) external whenNotPaused onlyWithRole(DETOKENIZER_ROLE) {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Finalize escrow request
        IToucanCarbonOffsetsEscrow(escrow).finalizeDetokenizationRequest(
            requestId,
            splitBalancingSerialNumber,
            splitRemainingSerialNumber
        );

        emit DetokenizationFinalized(requestId);
    }

    /// @notice Revert a detokenization request
    /// @param requestId The request id in the escrow contract that
    /// tracks the detokenization request
    function revertDetokenization(uint256 requestId)
        external
        whenNotPaused
        onlyWithRole(DETOKENIZER_ROLE)
    {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Mark escrow request as reverted
        IToucanCarbonOffsetsEscrow(escrow).revertDetokenizationRequest(
            requestId
        );

        emit DetokenizationReverted(requestId);
    }

    /// @notice Finalize a retirement request by burning its amount of TCO2 and minting a certificate for the
    /// beneficiary. In case the amount requested is smaller than the total amount of TCO2 in the batches, the last
    /// batch is split into two new batches, one that balances the total to be the amount requested and the other with
    /// the remaining amount.
    /// @dev Callable only by a retirement approver.
    /// @param requestId The ID of the request to finalize.
    /// @param splitBalancingSerialNumber The serial number of the new batch that balances the total amount to be the
    /// amount requested. This batch will be retired with the rest of the batches. Ignored if no splitting is required.
    /// @param splitRemainingSerialNumber The serial number of the new batch with the remaining amount. This batch will
    /// not be retired and will be in Confirmed status. Ignored if no splitting is required.
    function finalizeRetirement(
        uint256 requestId,
        string calldata splitBalancingSerialNumber,
        string calldata splitRemainingSerialNumber
    ) external whenNotPaused onlyWithRole(RETIREMENT_ROLE) {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Finalize escrow request
        IToucanCarbonOffsetsEscrow(escrow).finalizeRetirementRequest(
            requestId,
            splitBalancingSerialNumber,
            splitRemainingSerialNumber
        );

        emit RetirementFinalized(requestId);
    }

    /// @notice Revert a retirement request
    /// @param requestId The request id in the escrow contract that
    /// tracks the retirement request
    function revertRetirement(uint256 requestId)
        external
        whenNotPaused
        onlyWithRole(RETIREMENT_ROLE)
    {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Mark escrow request as reverted
        IToucanCarbonOffsetsEscrow(escrow).revertRetirementRequest(requestId);

        emit RetirementReverted(requestId);
    }

    // ----------------------------------------
    //       Permissionless functions
    // ----------------------------------------

    /// @notice Request a detokenization of batch-NFTs. The amount of TCO2 to detokenize will be transferred from
    /// the user to an escrow contract.
    /// @dev This function is permissionless and can be called by anyone
    /// @param tokenIds Token IDs of one or more batches to detokenize
    /// @param amount The amount of TCO2 to detokenize, must be greater than zero and equal to or smaller than the
    /// total amount of the batches (and also greater then the total amount of all the batches except the last one)
    /// @return requestId The ID of the request in the escrow contract
    function requestDetokenization(uint256[] calldata tokenIds, uint256 amount)
        external
        nonFractional(amount)
        whenNotPaused
        returns (uint256 requestId)
    {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Create escrow contract request, and transfer TCO2s from sender to escrow contract
        require(approve(escrow, amount), Errors.TCO2_APPROVAL_AMT_FAILED);
        requestId = IToucanCarbonOffsetsEscrow(escrow)
            .createDetokenizationRequest(_msgSender(), amount, tokenIds);

        emit DetokenizationRequested(_msgSender(), amount, requestId, tokenIds);
    }

    /// @notice Request a retirement of TCO2s from batch-NFTs. The amount of TCO2s to retire will be transferred
    /// from the user to an escrow contract.
    /// @dev This function is permissionless and can be called by anyone
    /// @param params The parameters of the retirement request:
    ///     uint256[] tokenIds One or more batches to retire
    ///     uint256 amount The amount of TCO2 to retire, must be greater than zero and equal to or smaller than the
    /// total amount of the batches (and also greater then the total amount of all the batches except the last one)
    ///     string retiringEntityString The name of the retiring entity
    ///     address beneficiary The address of the beneficiary of the retirement
    ///     string beneficiaryString The name of the beneficiary of the retirement
    ///     string retirementMessage A message to be included in the retirement certificate
    ///     string beneficiaryLocation The location of the beneficiary of the retirement
    ///     string consumptionCountryCode The country code of the consumption location
    ///     uint256 consumptionPeriodStart The start of the consumption period, in seconds since the epoch
    ///     uint256 consumptionPeriodEnd The end of the consumption period, in seconds since the epoch
    /// @return requestId The ID of the request in the escrow contract
    function requestRetirement(CreateRetirementRequestParams calldata params)
        external
        nonFractional(params.amount)
        whenNotPaused
        returns (uint256 requestId)
    {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Create escrow contract request, and trasnfer TCO2s from sender to escrow contract
        require(
            approve(escrow, params.amount),
            Errors.TCO2_APPROVAL_AMT_FAILED
        );
        requestId = IToucanCarbonOffsetsEscrow(escrow).createRetirementRequest(
            _msgSender(),
            params
        );

        emit RetirementRequested(_msgSender(), requestId, params);
    }

    // ----------------------------------------
    //       Internal functions
    // ----------------------------------------

    function retireAndMintCertificateForEntity(
        address retiringEntity,
        CreateRetirementRequestParams calldata params
    ) external virtual onlyEscrow {
        _retireAndMintCertificate(retiringEntity, params);
    }
}
