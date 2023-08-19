// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsBase.sol';

/// @notice Base contract that can be reused between different TCO2
/// implementations that need to work with batch NFTs
abstract contract ToucanCarbonOffsetsWithBatchBase is
    IERC721Receiver,
    ToucanCarbonOffsetsBase
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

    // ----------------------------------------
    //       Admin functions
    // ----------------------------------------

    /// @notice Finalize a detokenization request
    /// @param requestId The request id in the escrow contract that
    /// tracks the detokenization request
    function finalizeDetokenization(uint256 requestId)
        external
        whenNotPaused
        onlyWithRole(DETOKENIZER_ROLE)
    {
        address tcnRegistry = contractRegistry;
        address batchNFT = IToucanContractRegistry(tcnRegistry)
            .carbonOffsetBatchesAddress();
        address escrow = IToucanContractRegistry(tcnRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Fetch batch NFT IDs from escrow request
        DetokenizationRequest memory request = IToucanCarbonOffsetsEscrow(
            escrow
        ).detokenizationRequests(requestId);

        uint256 batchIdLength = request.batchTokenIds.length;
        // Loop through batches in the request and finalize them
        // while keeping track of the total TCO2 amount to burn
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < batchIdLength; ) {
            ICarbonOffsetBatches(batchNFT)
                .setStatusForDetokenizationOrRetirement(
                    request.batchTokenIds[i],
                    BatchStatus.DetokenizationFinalized
                );

            unchecked {
                ++i;
            }
        }

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
        address tcnRegistry = contractRegistry;
        address batchNFT = IToucanContractRegistry(tcnRegistry)
            .carbonOffsetBatchesAddress();
        address escrow = IToucanContractRegistry(tcnRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        // Fetch batch NFT IDs from escrow request
        DetokenizationRequest memory request = IToucanCarbonOffsetsEscrow(
            escrow
        ).detokenizationRequests(requestId);

        uint256 batchIdLength = request.batchTokenIds.length;
        // Loop through batches in the request and revert them to Confirmed
        // while keeping track of the total amount to transfer back to the user
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < batchIdLength; ) {
            ICarbonOffsetBatches(batchNFT)
                .setStatusForDetokenizationOrRetirement(
                    request.batchTokenIds[i],
                    BatchStatus.Confirmed
                );

            unchecked {
                ++i;
            }
        }

        // Mark escrow request as reverted
        IToucanCarbonOffsetsEscrow(escrow).revertDetokenizationRequest(
            requestId
        );

        emit DetokenizationReverted(requestId);
    }

    /// @notice Defractionalize batch NFT by burning the amount
    /// of TCO2 from the sender and transfer the batch NFT that
    /// was selected to the sender.
    /// The only valid sender currently is the TCO2 factory owner.
    /// @param tokenId The batch NFT to defractionalize from the TCO2
    function defractionalize(uint256 tokenId)
        external
        whenNotPaused
        onlyFactoryOwner
    {
        address batchNFT = IToucanContractRegistry(contractRegistry)
            .carbonOffsetBatchesAddress();

        // Fetch and burn amount of the NFT to be defractionalized
        (
            ,
            uint256 batchAmount,
            BatchStatus status
        ) = _getNormalizedDataFromBatch(batchNFT, tokenId);
        require(status == BatchStatus.Confirmed, 'Batch not confirmed');
        _burn(msg.sender, batchAmount);

        // Transfer batch NFT to sender
        IERC721(batchNFT).transferFrom(address(this), msg.sender, tokenId);
    }

    // ----------------------------------------
    //       Permissionless functions
    // ----------------------------------------

    /// @notice Request a detokenization of a batch NFT
    /// @param tokenIds One or more batches to detokenize
    /// @param amount The amount of TCO2 to detokenize
    /// Currently the amount must match the batch quantity
    /// @return The ID of the request in the escrow contract
    /// @dev This function is permissionless and can be called
    /// by anyone
    function requestDetokenization(uint256[] calldata tokenIds, uint256 amount)
        external
        whenNotPaused
        returns (uint256)
    {
        address tcnRegistry = contractRegistry;
        address batchNFT = IToucanContractRegistry(tcnRegistry)
            .carbonOffsetBatchesAddress();
        address escrow = IToucanContractRegistry(tcnRegistry)
            .toucanCarbonOffsetsEscrowAddress();

        //slither-disable-next-line uninitialized-local
        uint256 totalAmount;
        {
            // Stack too deep workaround

            // Loop through batches in the request and set them to DetokenizationRequested
            // while keeping track of the total amount to transfer from the user
            uint256 batchIdLength = tokenIds.length;
            //slither-disable-next-line uninitialized-local
            for (uint256 i; i < batchIdLength; ) {
                uint256 tokenId = tokenIds[i];
                (, uint256 batchAmount, ) = _getNormalizedDataFromBatch(
                    batchNFT,
                    tokenId
                );
                totalAmount += batchAmount;

                // Transition batch status to DetokenizationRequested
                ICarbonOffsetBatches(batchNFT)
                    .setStatusForDetokenizationOrRetirement(
                        tokenId,
                        BatchStatus.DetokenizationRequested
                    );

                unchecked {
                    ++i;
                }
            }
        }

        // Current requirement is that the total batch quantity matches the provided
        // amount. In the future this requirement should be removed in favor of
        // performing batch splitting.
        require(amount == totalAmount, 'Batch amount mismatch');

        // Create escrow contract request
        require(approve(escrow, amount), 'Approval failed');
        uint256 requestId = IToucanCarbonOffsetsEscrow(escrow)
            .createDetokenizationRequest(_msgSender(), amount, tokenIds);
        emit DetokenizationRequested(_msgSender(), amount, requestId, tokenIds);

        return requestId;
    }

    /// @notice Receive hook to fractionalize Batch-NFTs into ERC20's
    /// @dev Function is called with `operator` as `msg.sender` in a reference implementation by OZ
    /// `from` is the previous owner, not necessarily the same as operator.
    /// The hook checks if NFT collection is whitelisted and next if attributes are matching this ERC20 contract
    function onERC721Received(
        address, /* operator */
        address from,
        uint256 tokenId,
        bytes calldata /* data */
    ) external virtual override whenNotPaused returns (bytes4) {
        // msg.sender is the CarbonOffsetBatches contract
        require(
            checkWhiteListed(msg.sender),
            'Error: Batch-NFT not from whitelisted contract'
        );

        (
            uint256 gotVintageTokenId,
            uint256 quantity,
            BatchStatus status
        ) = _getNormalizedDataFromBatch(msg.sender, tokenId);
        require(
            gotVintageTokenId == projectVintageTokenId,
            'Error: non-matching NFT'
        );
        require(status == BatchStatus.Confirmed, 'BatchNFT not yet confirmed');
        require(
            getRemaining() >= quantity,
            'Error: Quantity in batch is higher than total vintages'
        );

        minterToId[from] = tokenId;
        IToucanCarbonOffsetsFactory tco2Factory = IToucanCarbonOffsetsFactory(
            IToucanContractRegistry(contractRegistry)
                .toucanCarbonOffsetsFactoryAddress(standardRegistry())
        );
        address bridgeFeeReceiver = tco2Factory.bridgeFeeReceiverAddress();

        if (bridgeFeeReceiver == address(0x0)) {
            // @dev if no bridge fee receiver address is set, mint without fees
            _mint(from, quantity);
        } else {
            // @dev calculate bridge fees
            (uint256 feeAmount, uint256 feeBurnAmount) = tco2Factory
                .getBridgeFeeAndBurnAmount(quantity);
            _mint(from, quantity - feeAmount);
            address bridgeFeeBurnAddress = tco2Factory.bridgeFeeBurnAddress();
            if (bridgeFeeBurnAddress != address(0x0) && feeBurnAmount > 0) {
                feeAmount -= feeBurnAmount;
                _mint(bridgeFeeReceiver, feeAmount);
                _mint(bridgeFeeBurnAddress, feeBurnAmount);
                emit FeePaid(from, feeAmount);
                emit FeeBurnt(from, feeBurnAmount);
            } else if (feeAmount > 0) {
                _mint(bridgeFeeReceiver, feeAmount);
                emit FeePaid(from, feeAmount);
            }
        }

        return this.onERC721Received.selector;
    }

    // ----------------------------------------
    //       Internal functions
    // ----------------------------------------

    function _getNormalizedDataFromBatch(address cob, uint256 tokenId)
        internal
        view
        returns (
            uint256,
            uint256,
            BatchStatus
        )
    {
        (
            uint256 vintageTokenId,
            uint256 quantity,
            BatchStatus status
        ) = ICarbonOffsetBatches(cob).getBatchNFTData(tokenId);
        return (vintageTokenId, quantity * 10**decimals(), status);
    }

    /// @dev Internal helper to check if CarbonOffsetBatches is whitelisted (official)
    function checkWhiteListed(address collection)
        internal
        view
        virtual
        returns (bool)
    {
        if (
            collection ==
            IToucanContractRegistry(contractRegistry)
                .carbonOffsetBatchesAddress()
        ) {
            return true;
        } else {
            return false;
        }
    }
}
