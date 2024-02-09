// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsBase.sol';
import './ToucanCarbonOffsetsWithBatchBaseTypes.sol';
import './ToucanCarbonOffsetsWithBatchBase.sol';
import '../libraries/Errors.sol';

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

        // Fetch batch NFT IDs from escrow request
        DetokenizationRequest memory request = IToucanCarbonOffsetsEscrow(
            escrow
        ).detokenizationRequests(requestId);

        _checkFinalizeRequestAndSplit(
            request.amount,
            request.batchTokenIds,
            splitBalancingSerialNumber,
            splitRemainingSerialNumber
        );
        _updateBatchStatuses(
            request.batchTokenIds,
            BatchStatus.DetokenizationFinalized
        );
        // Finalize escrow request
        IToucanCarbonOffsetsEscrow(escrow).finalizeDetokenizationRequest(
            requestId
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

        // Fetch batch NFT IDs from escrow request
        DetokenizationRequest memory request = IToucanCarbonOffsetsEscrow(
            escrow
        ).detokenizationRequests(requestId);

        _updateBatchStatuses(request.batchTokenIds, BatchStatus.Confirmed);

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

        // Fetch batch NFT IDs from escrow request
        RetirementRequest memory request = IToucanCarbonOffsetsEscrow(escrow)
            .retirementRequests(requestId);

        _checkFinalizeRequestAndSplit(
            request.amount,
            request.batchTokenIds,
            splitBalancingSerialNumber,
            splitRemainingSerialNumber
        );
        _updateBatchStatuses(
            request.batchTokenIds,
            BatchStatus.RetirementFinalized
        );
        // Finalize escrow request
        IToucanCarbonOffsetsEscrow(escrow).finalizeRetirementRequest(requestId);

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

        // Fetch batch NFT IDs from escrow request
        RetirementRequest memory request = IToucanCarbonOffsetsEscrow(escrow)
            .retirementRequests(requestId);

        _updateBatchStatuses(request.batchTokenIds, BatchStatus.Confirmed);

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
        _prepareForRequest(
            escrow,
            amount,
            tokenIds,
            BatchStatus.DetokenizationRequested
        );

        // Create escrow contract request, and transfer TCO2s from sender to escrow contract
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
        _prepareForRequest(
            escrow,
            params.amount,
            params.tokenIds,
            BatchStatus.RetirementRequested
        );

        // Create escrow contract request, and trasnfer TCO2s from sender to escrow contract
        requestId = IToucanCarbonOffsetsEscrow(escrow).createRetirementRequest(
            _msgSender(),
            params
        );

        emit RetirementRequested(_msgSender(), requestId, params);
    }

    // ----------------------------------------
    //       Internal functions
    // ----------------------------------------

    /// @dev internal function to check conditions for a detokenization or retirement request, update batch
    /// statuses and approve the requested amount of TCO2s from the user to the escrow contract.
    /// conditions checked:
    /// - amount requested is greater than zero
    /// - amount requested is equal to or less than the total amount of the batches
    /// - if amount requested is strictly less than total amount, it must be smaller than the total amount of all the
    ///   batches except the last one
    function _prepareForRequest(
        address escrow,
        uint256 amount,
        uint256[] calldata tokenIds,
        BatchStatus status
    ) internal {
        require(amount != 0, Errors.TCO2_BATCH_AMT_INVALID);
        (uint256 totalAmount, uint256 lastBatchAmount) = _updateBatchStatuses(
            tokenIds,
            status
        );

        // Check that amount requested is equal to or less than the total amount of the batches
        if (amount > totalAmount) revert(Errors.TCO2_BATCH_AMT_INVALID);
        // if amount requested is less than total amount, it means we will split the last batch, and so we need the
        // amount of the rest of the batches to be less than the amount requested. This should help avoid grieving
        // attacks where any user with a fraction of TCO2 can request to lock all batches for a TCO2.
        // in case the amount requested is equal to the total amount, this check will always pass.
        // NOTE: no-op in case there's only 1 batch in the request
        if (totalAmount - lastBatchAmount >= amount)
            revert(Errors.TCO2_BATCH_AMT_INVALID);

        // Approve escrow contract to transfer TCO2s from user
        require(approve(escrow, amount), Errors.TCO2_APPROVAL_AMT_FAILED);
    }

    function _updateBatchStatuses(uint256[] memory tokenIds, BatchStatus status)
        internal
        returns (uint256 totalAmount, uint256 lastBatchAmount)
    {
        address batchNFT = IToucanContractRegistry(contractRegistry)
            .carbonOffsetBatchesAddress();
        // Loop through batches in the request and set them to the batch status provided
        // while keeping track of the total amount to transfer from the user
        uint256 batchIdLength = tokenIds.length;
        uint256 batchAmount = 0;
        for (uint256 i = 0; i < batchIdLength; ) {
            uint256 tokenId = tokenIds[i];
            (, batchAmount, ) = _getNormalizedDataFromBatch(batchNFT, tokenId);
            totalAmount += batchAmount;
            // Transition batch status to updated status
            ICarbonOffsetBatches(batchNFT)
                .setStatusForDetokenizationOrRetirement(tokenId, status);
            unchecked {
                ++i;
            }
        }
        lastBatchAmount = batchAmount;
    }

    function retireAndMintCertificateForEntity(
        address retiringEntity,
        CreateRetirementRequestParams calldata params
    ) external virtual onlyEscrow {
        _retireAndMintCertificate(retiringEntity, params);
    }

    /// @dev Check if splitting is required and split the last batch if so
    function _checkFinalizeRequestAndSplit(
        uint256 amount,
        uint256[] memory batchTokenIds,
        string calldata splitBalancingSerialNumber,
        string calldata splitRemainingSerialNumber
    ) internal {
        ICarbonOffsetBatches carbonOffsetBatches = ICarbonOffsetBatches(
            IToucanContractRegistry(contractRegistry)
                .carbonOffsetBatchesAddress()
        );
        uint256 totalBatchesAmount = _getTotalBatchesAmount(
            carbonOffsetBatches,
            batchTokenIds
        );
        uint256 normalizedAmount = _TCO2AmountToBatchAmount(amount);
        // if the amount requested is not equal to the total amount of TCO2 in the batches, we need to split the last
        // batch
        // NOTE: the batches are split according to normalized amounts, so if the amount requested is not a multiple of
        // the TCO2 decimals, the batches retired will not match the amount of TCO2 burnt
        if (normalizedAmount < totalBatchesAmount) {
            _executeSplit(
                carbonOffsetBatches,
                batchTokenIds,
                splitBalancingSerialNumber,
                splitRemainingSerialNumber,
                totalBatchesAmount - normalizedAmount
            );
        }
    }

    function _getTotalBatchesAmount(
        ICarbonOffsetBatches carbonOffsetBatches,
        uint256[] memory batchTokenIds
    ) internal view returns (uint256 totalBatchesAmount) {
        for (uint256 i = 0; i < batchTokenIds.length; ++i) {
            (, uint256 batchAmount, ) = carbonOffsetBatches.getBatchNFTData(
                batchTokenIds[i]
            );
            totalBatchesAmount += batchAmount;
        }
    }

    function _executeSplit(
        ICarbonOffsetBatches carbonOffsetBatches,
        uint256[] memory batchTokenIds,
        string calldata splitBalancingSerialNumber,
        string calldata splitRemainingSerialNumber,
        uint256 newAmount
    ) internal {
        require(
            bytes(splitBalancingSerialNumber).length != 0 &&
                bytes(splitRemainingSerialNumber).length != 0,
            Errors.TCO2_MISSING_SERIALS
        );
        uint256 newTokenId = carbonOffsetBatches.split(
            batchTokenIds[batchTokenIds.length - 1],
            splitBalancingSerialNumber,
            splitRemainingSerialNumber,
            newAmount
        );
        // change the status of the new batch with the remaining amount to Confirmed
        carbonOffsetBatches.setStatusForDetokenizationOrRetirement(
            newTokenId,
            BatchStatus.Confirmed
        );
    }
}
