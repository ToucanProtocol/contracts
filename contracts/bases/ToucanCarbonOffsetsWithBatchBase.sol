// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsBase.sol';
import './ToucanCarbonOffsetsWithBatchBaseTypes.sol';
import '../libraries/Errors.sol';

/// @notice Base contract that can be reused between different TCO2
/// implementations that need to work with batch NFTs
abstract contract ToucanCarbonOffsetsWithBatchBase is
    IERC721Receiver,
    ToucanCarbonOffsetsBase
{
    // ----------------------------------------
    //       Admin functions
    // ----------------------------------------

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
        require(
            status == BatchStatus.Confirmed,
            Errors.TCO2_BATCH_NOT_CONFIRMED
        );
        _burn(msg.sender, batchAmount);

        // Transfer batch NFT to sender
        IERC721(batchNFT).transferFrom(address(this), msg.sender, tokenId);
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
            Errors.TCO2_BATCH_NOT_WHITELISTED
        );

        (
            uint256 gotVintageTokenId,
            uint256 quantity,
            BatchStatus status
        ) = _getNormalizedDataFromBatch(msg.sender, tokenId);
        require(
            gotVintageTokenId == _projectVintageTokenId,
            Errors.TCO2_NON_MATCHING_NFT
        );
        // don't mint TCO2s for received batches that are in detokenization/retirement requested status
        if (
            status == BatchStatus.DetokenizationRequested ||
            status == BatchStatus.RetirementRequested
        ) return this.onERC721Received.selector;
        // mint TCO2s for received batches that are in confirmed status
        require(
            status == BatchStatus.Confirmed,
            Errors.TCO2_BATCH_NOT_CONFIRMED
        );
        require(getRemaining() >= quantity, Errors.TCO2_QTY_HIGHER);

        minterToId[from] = tokenId;
        IToucanCarbonOffsetsFactory tco2Factory = IToucanCarbonOffsetsFactory(
            IToucanContractRegistry(contractRegistry)
                .toucanCarbonOffsetsFactoryAddress(standardRegistry())
        );
        address bridgeFeeReceiver = tco2Factory.bridgeFeeReceiverAddress();

        if (bridgeFeeReceiver == address(0x0)) {
            // if no bridge fee receiver address is set, mint without fees
            _mint(from, quantity);
        } else {
            // calculate bridge fees
            (uint256 feeAmount, uint256 feeBurnAmount) = tco2Factory
                .getBridgeFeeAndBurnAmount(quantity);
            _mint(from, quantity - feeAmount);
            address bridgeFeeBurnAddress = tco2Factory.bridgeFeeBurnAddress();
            // we mint the burn fee to the bridge fee burn address so it can be retired later.
            // if there is no address configured we just mint the full amount to the bridge fee receiver.
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
        return (vintageTokenId, _batchAmountToTCO2Amount(quantity), status);
    }

    function _batchAmountToTCO2Amount(uint256 batchAmount)
        internal
        view
        returns (uint256)
    {
        return batchAmount * 10**decimals();
    }

    function _TCO2AmountToBatchAmount(uint256 TCO2Amount)
        internal
        view
        returns (uint256)
    {
        return TCO2Amount / 10**decimals();
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
