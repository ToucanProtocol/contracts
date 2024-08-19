// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/ICarbonOffsetBatches.sol';
import './interfaces/ICarbonProjectVintages.sol';
import './interfaces/IToucanCarbonOffsets.sol';
import './interfaces/IToucanCarbonOffsetsFactory.sol';
import './interfaces/IToucanContractRegistry.sol';
import './CarbonOffsetBatchesStorage.sol';
import {Errors} from './libraries/Errors.sol';
import './libraries/ProjectVintageUtils.sol';
import './libraries/Modifiers.sol';
import './libraries/Strings.sol';

/// @title A contract for managing batches of carbon credits
/// @notice Also referred to as Batch-Contract (formerly BatchCollection)
/// Contract that tokenizes retired/cancelled CO2 credits into NFTs via a claims process
contract CarbonOffsetBatches is
    ICarbonOffsetBatches,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ProjectVintageUtils,
    Modifiers,
    CarbonOffsetBatchesStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using Strings for string;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.5.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @dev All roles related to accessing this contract
    bytes32 public constant VERIFIER_ROLE = keccak256('VERIFIER_ROLE');
    bytes32 public constant TOKENIZER_ROLE = keccak256('TOKENIZER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event BatchMinted(address sender, uint256 tokenId);
    event BatchUpdated(uint256 tokenId, string serialNumber, uint256 quantity);
    event BatchLinkedWithVintage(
        uint256 tokenId,
        uint256 projectVintageTokenId
    );
    event BatchComment(
        uint256 tokenId,
        uint256 commentId,
        address sender,
        string comment
    );
    event BatchStatusUpdate(uint256 tokenId, BatchStatus status);
    event RegistrySupported(string registry, bool isSupported);
    event Tokenized(
        uint256 tokenId,
        address tco2,
        address indexed recipient,
        uint256 amount
    );

    event Split(uint256 tokenId, uint256 newTokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address _contractRegistry)
        external
        virtual
        initializer
    {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'Toucan Protocol: Carbon Offset Batches',
            'TOUCAN-COB'
        );
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        contractRegistry = _contractRegistry;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    // ------------------------
    // Poor person's modifiers
    // ------------------------

    function onlyWithRole(bytes32 role) internal view {
        if (!hasRole(role, msg.sender)) revert(Errors.COB_INVALID_CALLER);
    }

    function onlyEscrow() internal view {
        address escrow = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsEscrowAddress();
        if (escrow != msg.sender) revert(Errors.COB_INVALID_CALLER);
    }

    function onlyPending(uint256 tokenId) internal view {
        if (nftList[tokenId].status != BatchStatus.Pending)
            revert(Errors.COB_INVALID_STATUS);
    }

    function onlyApprovedOrOwner(uint256 tokenId) internal view {
        if (!_isApprovedOrOwner(_msgSender(), tokenId))
            revert(Errors.COB_TRANSFER_NOT_APPROVED);
    }

    function onlyVerifierOrBatchOwner(uint256 tokenId) internal view {
        if (
            ownerOf(tokenId) != _msgSender() &&
            !hasRole(VERIFIER_ROLE, msg.sender)
        ) revert(Errors.COB_NOT_VERIFIER_OR_BATCH_OWNER);
    }

    function onlyValidNewStatus(BatchStatus statusA, BatchStatus statusB)
        internal
        pure
    {
        if (statusA != statusB) revert(Errors.COB_INVALID_NEW_STATUS);
    }

    function onlyUnpaused() internal view {
        if (paused()) revert(Errors.COB_PAUSED_CONTRACT);
    }

    // ------------------------
    //      Admin functions
    // ------------------------

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), callable only by the Toucan contract registry or the contract owner
    function pause() external onlyBy(contractRegistry, owner()) {
        _pause();
    }

    /// @notice Emergency function to re-enable contract's core functionality after being paused
    /// @dev wraps _unpause(), callable only by the Toucan contract registry or the contract owner
    function unpause() external onlyBy(contractRegistry, owner()) {
        _unpause();
    }

    /// @notice Admin function to set the contract registry
    /// @dev Callable only by the contract owner
    /// @param _address The address of the new contract registry
    function setToucanContractRegistry(address _address) external onlyOwner {
        contractRegistry = _address;
    }

    /// @notice Admin function to set whether a registry is supported
    /// @dev Callable only by the contract owner; executable only if the status can be changed
    /// @param registry The registry to set supported status for
    /// @param isSupported Whether the registry should be supported
    function setSupportedRegistry(string memory registry, bool isSupported)
        external
        onlyOwner
    {
        if (supportedRegistries[registry] == isSupported)
            revert(Errors.COB_ALREADY_SUPPORTED);

        supportedRegistries[registry] = isSupported;
        emit RegistrySupported(registry, isSupported);
    }

    /// @dev internal helper function to set the status and emit an event
    function _updateStatus(uint256 tokenId, BatchStatus newStatus)
        internal
        virtual
    {
        nftList[tokenId].status = newStatus;
        emit BatchStatusUpdate(tokenId, newStatus);
    }

    /// @notice Set the status of a batch to a new status
    /// for detokenization or retirement requests.
    ///
    /// Valid transitions:
    /// - In case a user makes a request:
    ///   - Confirmed -> DetokenizationRequested
    ///   - Confirmed -> RetirementRequested
    /// - In case a DETOKENIZER_ROLE in TCO2 finalizes a request:
    ///   - DetokenizationRequested -> DetokenizationFinalized
    ///   - RetirementRequested -> RetirementFinalized
    /// - In case a DETOKENIZER_ROLE in TCO2 reverts a request:
    ///   - DetokenizationRequested -> Confirmed
    ///   - RetirementRequested -> Confirmed
    ///
    /// @dev Callable only by the escrow contract, only for batches owned by a TCO2 contract
    /// @param tokenId The token ID of the batch
    /// @param newStatus The new status to set
    function setStatusForDetokenizationOrRetirement(
        uint256 tokenId,
        BatchStatus newStatus
    ) external virtual override {
        onlyUnpaused();
        onlyEscrow();
        address tokenOwner = ownerOf(tokenId);
        if (!IToucanContractRegistry(contractRegistry).isValidERC20(tokenOwner))
            revert(Errors.COB_INVALID_BATCH_OWNER);
        BatchStatus currentStatus = nftList[tokenId].status;
        // Only valid transition to a requested status is from a confirmed batch
        if (
            newStatus == BatchStatus.DetokenizationRequested ||
            newStatus == BatchStatus.RetirementRequested
        ) {
            onlyValidNewStatus(currentStatus, BatchStatus.Confirmed);
            // Only valid transition to a finalized status is from a requested status
        } else if (newStatus == BatchStatus.DetokenizationFinalized) {
            onlyValidNewStatus(
                currentStatus,
                BatchStatus.DetokenizationRequested
            );
        } else if (newStatus == BatchStatus.RetirementFinalized) {
            onlyValidNewStatus(currentStatus, BatchStatus.RetirementRequested);
            // Only valid transition to a confirmed status is from a requested status
        } else if (newStatus == BatchStatus.Confirmed) {
            if (
                currentStatus != BatchStatus.DetokenizationRequested &&
                currentStatus != BatchStatus.RetirementRequested
            ) revert(Errors.COB_INVALID_NEW_STATUS);
        } else {
            revert(Errors.COB_INVALID_NEW_STATUS);
        }
        _updateStatus(tokenId, newStatus);
    }

    /// @notice Function to approve a Batch-NFT after validation.
    /// Fractionalization requires status Confirmed.
    /// @dev Callable only by verifiers, only for pending batches. This flow requires a previous linking with a vintage
    /// @param tokenId The token ID of the batch
    function confirmBatch(uint256 tokenId) external virtual {
        onlyUnpaused();
        onlyWithRole(VERIFIER_ROLE);
        _confirmBatch(tokenId);
    }

    /// @dev Internal function that requires a previous linking with a `projectVintageTokenId`.
    function _confirmBatch(uint256 _tokenId) internal {
        if (!_exists(_tokenId)) revert(Errors.COB_NOT_EXISTS);
        onlyPending(_tokenId);
        if (nftList[_tokenId].projectVintageTokenId == 0)
            revert(Errors.COB_MISSING_VINTAGE);
        if (serialNumberApproved[nftList[_tokenId].serialNumber])
            revert(Errors.COB_ALREADY_APPROVED);
        // setting serialnumber as unique after confirmation
        serialNumberApproved[nftList[_tokenId].serialNumber] = true;
        _updateStatus(_tokenId, BatchStatus.Confirmed);
    }

    /// @notice Reject Batch-NFTs, e.g. if the serial number entered is incorrect.
    /// @dev Callable only by verifiers, only for pending batches.
    /// @param tokenId The token ID of the batch
    function rejectBatch(uint256 tokenId) public virtual {
        onlyUnpaused();
        onlyWithRole(VERIFIER_ROLE);
        onlyPending(tokenId);

        // unsetting serialnumber with rejection
        serialNumberApproved[nftList[tokenId].serialNumber] = false;
        _updateStatus(tokenId, BatchStatus.Rejected);
    }

    /// @notice Function to reject Batch-NFTs, including a reason to be displayed to the user.
    function rejectWithComment(uint256 tokenId, string memory comment)
        external
        virtual
    {
        onlyUnpaused();
        rejectBatch(tokenId);
        _addComment(tokenId, comment);
    }

    /// @dev admin function to reject a previously approved batch
    /// Requires that the Batch-NFT has not been fractionalized yet
    function rejectApprovedWithComment(uint256 tokenId, string memory comment)
        external
    {
        onlyUnpaused();
        onlyWithRole(VERIFIER_ROLE);
        if (nftList[tokenId].status != BatchStatus.Confirmed)
            revert(Errors.COB_NOT_CONFIRMED);
        if (
            IToucanContractRegistry(contractRegistry).isValidERC20(
                ownerOf(tokenId)
            )
        ) revert(Errors.COB_ALREADY_FRACTIONALIZED);
        _updateStatus(tokenId, BatchStatus.Rejected);
        _addComment(tokenId, comment);
    }

    /// @notice Set batches back to pending after a rejection. This can
    /// be useful if there was an issue unrelated to the on-chain data of the
    /// batch, e.g. the batch was incorrectly rejected.
    /// @dev Callable only by verifiers, only for rejected batches.
    /// @param tokenId The token ID of the batch
    function setToPending(uint256 tokenId) external virtual {
        onlyUnpaused();
        onlyWithRole(VERIFIER_ROLE);
        if (nftList[tokenId].status != BatchStatus.Rejected)
            revert(Errors.COB_NOT_REJECTED);
        _updateStatus(tokenId, BatchStatus.Pending);
    }

    /// @notice Link Batch-NFT with Vintage
    /// @dev Function for alternative flow where Batch-NFT approval is done separately. Callable only by verifiers.
    /// @param tokenId The token ID of the batch
    /// @param projectVintageTokenId The token ID of the vintage
    function linkWithVintage(uint256 tokenId, uint256 projectVintageTokenId)
        external
        virtual
    {
        onlyUnpaused();
        onlyWithRole(VERIFIER_ROLE);
        _linkWithVintage(tokenId, projectVintageTokenId);
    }

    // @dev Function to internally link with Vintage when Batch-NFT approval is done seperately.
    function _linkWithVintage(uint256 _tokenId, uint256 _projectVintageTokenId)
        internal
    {
        checkProjectVintageTokenExists(
            contractRegistry,
            _projectVintageTokenId
        );
        nftList[_tokenId].projectVintageTokenId = _projectVintageTokenId;
        emit BatchLinkedWithVintage(_tokenId, _projectVintageTokenId);
    }

    /// @notice Link with vintage and confirm Batch-NFT
    /// @dev Function for main approval flow. Callable only by verifiers.
    /// @param tokenId The token ID of the batch
    /// @param projectVintageTokenId The token ID of the vintage
    function confirmBatchWithVintage(
        uint256 tokenId,
        uint256 projectVintageTokenId
    ) external virtual {
        onlyUnpaused();
        onlyWithRole(VERIFIER_ROLE);
        // We don't want this to be a "backdoor" for modifying the vintage; it
        // could be insecure or allow accidents to happen, and it would also
        // result in BatchLinkedWithVintage being emitted more than once per
        // batch.
        if (nftList[tokenId].projectVintageTokenId != 0)
            revert(Errors.COB_VINTAGE_ALREADY_SET);
        _linkWithVintage(tokenId, projectVintageTokenId);
        _confirmBatch(tokenId);
    }

    /// @notice Remove a previously approved serial number
    /// @dev Function to remove uniqueness for previously set serialnumbers. Callable only by verifiers.
    /// N.B. even though (technically speaking) calling this to complete the
    /// upgrade to a fixed contract is the responsibility of the contract's
    /// owner (deployer), in practice that is a multi-sig even before upgrade,
    /// and unsetting a bunch of serials via multi-sig is not practical.
    /// So instead we allow the verifiers to do it.
    /// @param serialNumber The serial number to unset
    function unsetSerialNumber(string memory serialNumber) external {
        onlyWithRole(VERIFIER_ROLE);
        serialNumberApproved[serialNumber] = false;
    }

    // ----------------------------------
    //  (Semi-)Permissionless functions
    // ----------------------------------

    /// @notice Permissionlessly mint empty Batch-NFTs
    /// Entry point to the carbon bridging process.
    /// @dev To be updated by NFT owner after serial number has been provided
    /// @param to The address the NFT should be minted to. This should be the user.
    /// @return The token ID of the newly minted NFT
    function mintEmptyBatch(address to) external virtual returns (uint256) {
        onlyUnpaused();
        return _mintEmptyBatch(to, to);
    }

    /// @notice Permissionlessly mint empty Batch-NFTs
    /// Entry point to the carbon bridging process.
    /// @dev To be updated by NFT owner after serial number has been provided
    /// @param to The address the NFT should be minted to. This should be the user
    /// but can also be the CarbonOffsetBatches contract itself in case the batch-NFT
    /// is held temporarily by the contract before fractionalization (see tokenize()).
    /// @param onBehalfOf The address of user on behalf of whom the batch is minted
    /// @return newItemId The token ID of the newly minted NFT
    function _mintEmptyBatch(address to, address onBehalfOf)
        internal
        returns (uint256 newItemId)
    {
        newItemId = batchTokenCounter;
        unchecked {
            ++newItemId;
        }
        batchTokenCounter = newItemId;

        _safeMint(to, newItemId);
        nftList[newItemId].status = BatchStatus.Pending;

        emit BatchMinted(onBehalfOf, newItemId);
    }

    /// @notice Update Batch-NFT after Serialnumber has been verified
    /// @dev Data is usually inserted by the user (NFT owner) via the UI. Callable only by verifiers or the batch-NFT
    /// owner.
    /// @param tokenId The token ID of the batch
    /// @param serialNumber The serial number received from the registry/credit cancellation
    /// @param quantity Quantity in tCO2e, greater than 0
    /// @param uri Optional tokenURI with additional information
    function updateBatchWithData(
        uint256 tokenId,
        string memory serialNumber,
        uint256 quantity,
        string memory uri
    ) external virtual {
        onlyUnpaused();
        onlyVerifierOrBatchOwner(tokenId);
        onlyPending(tokenId);
        _updateSerialAndQuantity(tokenId, serialNumber, quantity);

        if (!uri.equals(nftList[tokenId].uri)) nftList[tokenId].uri = uri;
    }

    /// @notice Internal function that updates batch-NFT after serial number has been verified
    function _updateSerialAndQuantity(
        uint256 tokenId,
        string memory serialNumber,
        uint256 quantity
    ) internal {
        if (serialNumberApproved[serialNumber])
            revert(Errors.COB_ALREADY_APPROVED);
        if (quantity == 0) revert(Errors.COB_INVALID_QUANTITY);
        nftList[tokenId].serialNumber = serialNumber;
        nftList[tokenId].quantity = quantity;

        emit BatchUpdated(tokenId, serialNumber, quantity);
    }

    /// @notice Update batch-NFT with serial number and quantity only
    /// @dev Convenience function to only update serial number and quantity and not the serial/URI. Callable only by a
    /// verifier or the batch-NFT owner.
    /// @param tokenId The token ID of the batch
    /// @param newSerialNumber The serial number received from the registry/credit cancellation
    /// @param newQuantity Quantity in tCO2e, greater than 0
    function setSerialandQuantity(
        uint256 tokenId,
        string memory newSerialNumber,
        uint256 newQuantity
    ) external virtual {
        onlyUnpaused();
        onlyVerifierOrBatchOwner(tokenId);
        onlyPending(tokenId);
        _updateSerialAndQuantity(tokenId, newSerialNumber, newQuantity);
    }

    /// @notice Returns just the confirmation (approval) status of Batch-NFT
    /// @param tokenId The token ID of the batch
    function getConfirmationStatus(uint256 tokenId)
        external
        view
        virtual
        override
        returns (BatchStatus)
    {
        return nftList[tokenId].status;
    }

    /// @notice Returns all data for Batch-NFT
    /// @dev Used in TCO2 contract's receive hook `onERC721Received`
    /// @param tokenId The token ID of the batch
    /// @return projectVintageTokenId The token ID of the vintage
    /// @return quantity Quantity in tCO2e
    /// @return status The status of the batch
    function getBatchNFTData(uint256 tokenId)
        external
        view
        virtual
        override
        returns (
            uint256,
            uint256,
            BatchStatus
        )
    {
        if (!_exists(tokenId)) revert(Errors.COB_NOT_EXISTS);
        return (
            nftList[tokenId].projectVintageTokenId,
            nftList[tokenId].quantity,
            nftList[tokenId].status
        );
    }

    /// @notice Returns the serial number of a batch token id
    /// @param tokenId The token ID of the batch
    /// @return The serial number of the batch
    function getSerialNumber(uint256 tokenId)
        external
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert(Errors.COB_NOT_EXISTS);
        return nftList[tokenId].serialNumber;
    }

    /// @dev This is necessary because the automatically generated nftList
    /// getter will not include an array of comments in the returned tuple for
    /// gas reasons:
    /// https://docs.soliditylang.org/en/latest/contracts.html#visibility-and-getters
    function getComments(uint256 tokenId)
        external
        view
        virtual
        returns (string[] memory, address[] memory)
    {
        return (nftList[tokenId].comments, nftList[tokenId].commentAuthors);
    }

    /// @dev Overridden here because of function overloading issues with ethers.js
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        onlyApprovedOrOwner(tokenId);
        safeTransferFrom(from, to, tokenId, '');
    }

    /// @notice Automatically converts Batch-NFT to TCO2s (ERC20)
    /// @dev Only by the batch-NFT owner or approved operator, only if batch is confirmed.
    /// Batch-NFT is sent from the sender and TCO2s are transferred to the sender.
    /// Queries the factory to find the corresponding TCO2 contract
    /// Fractionalization happens via receive hook on `safeTransferFrom`
    /// @param tokenId The token ID of the batch
    function fractionalize(uint256 tokenId) external virtual {
        onlyApprovedOrOwner(tokenId);
        // Fractionalize by transferring the batch-NFT to the TCO2 contract.
        safeTransferFrom(
            _msgSender(),
            _getTCO2ForBatchTokenId(tokenId),
            tokenId,
            ''
        );
    }

    /// @dev returns the address of the TCO2 contract that corresponds to the batch-NFT
    function _getTCO2ForBatchTokenId(uint256 tokenId)
        internal
        view
        returns (address)
    {
        uint256 pvId = nftList[tokenId].projectVintageTokenId;
        IToucanContractRegistry tcnRegistry = IToucanContractRegistry(
            contractRegistry
        );

        // Fetch the registry from the vintage data first
        address vintages = tcnRegistry.carbonProjectVintagesAddress();
        VintageData memory data = ICarbonProjectVintages(vintages)
            .getProjectVintageDataByTokenId(pvId);

        // Now we can fetch the TCO2 factory for the carbon registry
        string memory carbonRegistry = data.registry;
        if (bytes(carbonRegistry).length == 0) {
            carbonRegistry = 'verra';
        }
        address tco2Factory = tcnRegistry.toucanCarbonOffsetsFactoryAddress(
            carbonRegistry
        );

        return IToucanCarbonOffsetsFactory(tco2Factory).pvIdtoERC20(pvId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IAccessControlUpgradeable).interfaceId ||
            ERC721Upgradeable.supportsInterface(interfaceId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory gateway) external onlyOwner {
        baseURI = gateway;
    }

    /// @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    /// based on the ERC721URIStorage implementation
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert(Errors.COB_NOT_EXISTS);

        string memory uri = nftList[tokenId].uri;
        // If there is no base URI, return the token URI.
        if (bytes(_baseURI()).length == 0) return uri;
        // If both are set, concatenate the baseURI and tokenURI
        if (bytes(uri).length > 0) return string.concat(_baseURI(), uri);

        return super.tokenURI(tokenId);
    }

    /// @dev Utilized here in order to disable transfers when paused
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        onlyUnpaused();
        super._beforeTokenTransfer(from, to, amount);
    }

    /// @notice Append a comment to a Batch-NFT
    /// @dev Don't allow the contract owner to comment.  When the contract owner
    /// can also be a verifier they should add them as a verifier first; this
    /// should prevent accidental comments from the wrong account.
    function addComment(uint256 tokenId, string memory comment) external {
        // this also checks that tokenId exists, otherwise ERC721Upgradeable.ownerOf would revert on nonexistent token
        onlyVerifierOrBatchOwner(tokenId);
        _addComment(tokenId, comment);
    }

    function _addComment(uint256 tokenId, string memory comment) internal {
        nftList[tokenId].comments.push() = comment;
        nftList[tokenId].commentAuthors.push() = _msgSender();
        emit BatchComment(
            tokenId,
            nftList[tokenId].comments.length,
            _msgSender(),
            comment
        );
    }

    /// @notice This function allows external APIs to tokenize their carbon credits
    /// @dev Callable only by tokenizers. Performs the full tokenization process: minting a batch-NFT, linking it with a project
    /// vintage, setting the quantity and serial number, confirming the batch, and fractionalizing it. The TCO2s are
    /// then transferred to the recipient.
    /// @param recipient Recipient of the tokens
    /// @param serialNumber Serial number of the carbon credits to be tokenized
    /// @param quantity Quantity to be tokenized in 1e18 format, greater than 0
    /// @param projectVintageTokenId The token ID of the vintage
    function tokenize(
        address recipient,
        string calldata serialNumber,
        uint256 quantity,
        uint256 projectVintageTokenId
    ) external {
        onlyUnpaused();
        onlyWithRole(TOKENIZER_ROLE);
        // Prepare and confirm batch
        uint256 tokenId = _mintEmptyBatch(address(this), recipient);
        _updateSerialAndQuantity(tokenId, serialNumber, quantity);
        _linkWithVintage(tokenId, projectVintageTokenId);
        _confirmBatch(tokenId);

        // Check existing TCO2 balance; to be used at the end
        // to send the exact TCO2 needed to the recipient.
        address tco2 = _getTCO2ForBatchTokenId(tokenId);
        if (tco2 == address(0)) revert(Errors.COB_TCO2_NOT_FOUND);
        string memory registry = IToucanCarbonOffsets(tco2).standardRegistry();
        if (!supportedRegistries[registry])
            revert(Errors.COB_REGISTRY_NOT_SUPPORTED);
        uint256 balanceBefore = IERC20Upgradeable(tco2).balanceOf(
            address(this)
        );

        // Fractionalize by transferring the batch-NFT to the TCO2 contract.
        _safeTransfer(address(this), tco2, tokenId, '');

        // Check that TCO2s were minted
        uint256 balanceAfter = IERC20Upgradeable(tco2).balanceOf(address(this));
        uint256 amount = balanceAfter - balanceBefore;

        //slither-disable-next-line incorrect-equality
        if (amount == 0) revert(Errors.COB_NO_TCO2_MINTED);

        // Transfer minted TCO2s to recipient.
        IERC20Upgradeable(tco2).safeTransfer(recipient, amount);
        emit Tokenized(tokenId, tco2, recipient, amount);
    }

    /// @notice Split a batch-NFT into two batch-NFTs, by creating a new batch-NFT and updating the old one.
    /// The old batch will have a new serial number and quantity will be reduced by the quantity of the new batch.
    /// @dev Callable only by the escrow contract, only for batches with status
    /// RetirementRequested or DetokenizationRequested. The TCO2 contract will also be the owner of the new batch and
    /// its status will be the same as the old batch.
    /// @param tokenId The token ID of the batch to split
    /// @param tokenIdNewSerialNumber The new serial number for the old batch
    /// @param newTokenIdSerialNumber The serial number for the new batch
    /// @param newTokenIdQuantity The quantity for the new batch, must be smaller than the old quantity and greater
    /// than 0
    /// @return newTokenId The token ID of the new batch
    function split(
        uint256 tokenId,
        string calldata tokenIdNewSerialNumber,
        string calldata newTokenIdSerialNumber,
        uint256 newTokenIdQuantity
    ) external returns (uint256 newTokenId) {
        onlyUnpaused();
        onlyEscrow();
        address tco2 = ownerOf(tokenId);
        if (!IToucanContractRegistry(contractRegistry).isValidERC20(tco2))
            revert(Errors.COB_INVALID_BATCH_OWNER);
        // Validate batch status
        BatchStatus status = nftList[tokenId].status;
        if (
            status != BatchStatus.RetirementRequested &&
            status != BatchStatus.DetokenizationRequested
        ) revert(Errors.COB_INVALID_STATUS);
        // Validate batch quantity
        if (nftList[tokenId].quantity <= newTokenIdQuantity)
            revert(Errors.COB_INVALID_QUANTITY);

        // keep old serial number to be able to unapprove it after checking and approving the new ones
        string memory oldSerialNumber = nftList[tokenId].serialNumber;
        // this also performs the check that the new quantity is smaller than the old quantity, otherwise it would
        // underflow and revert. in case it is equal to the old quantity, _updateSerialAndQuantity would revert on
        // quantity == 0
        _updateSerialAndQuantity(
            tokenId,
            tokenIdNewSerialNumber,
            nftList[tokenId].quantity - newTokenIdQuantity
        );
        serialNumberApproved[tokenIdNewSerialNumber] = true;

        // mint a new batch to be owned by the TCO2 contract
        newTokenId = _mintEmptyBatch(address(this), tco2);
        _updateSerialAndQuantity(
            newTokenId,
            newTokenIdSerialNumber,
            newTokenIdQuantity
        ); // here we would revert in case newTokenIdQuantity == 0
        serialNumberApproved[newTokenIdSerialNumber] = true;

        // unapprove the old serial number
        serialNumberApproved[oldSerialNumber] = false;

        // link the new batch with the vintage of the old batch
        _linkWithVintage(newTokenId, nftList[tokenId].projectVintageTokenId);

        // Copy the status from the old batch
        _updateStatus(newTokenId, status);

        // transfer new batch to TCO2 contract with the right status so that
        // it will not be fractionalized
        _safeTransfer(address(this), tco2, newTokenId, '');

        emit Split(tokenId, newTokenId);
    }

    function onERC721Received(
        address, /* operator */
        address from, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        // This hook is only used by the contract to mint batch-NFTs that
        // can be tokenized on behalf of end users.
        if (from != address(0)) revert(Errors.COB_ONLY_MINTS);
        return this.onERC721Received.selector;
    }
}
