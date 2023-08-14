// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/ICarbonOffsetBatches.sol';
import './interfaces/ICarbonProjectVintages.sol';
import './interfaces/IToucanCarbonOffsets.sol';
import './interfaces/IToucanContractRegistry.sol';
import './ToucanCarbonOffsetsFactory.sol';
import './CarbonOffsetBatchesStorage.sol';
import './libraries/Errors.sol';
import './libraries/ProjectVintageUtils.sol';
import './libraries/Modifiers.sol';
import './libraries/Strings.sol';

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
    using AddressUpgradeable for address;
    using Strings for string;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.3.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 5;

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

    /// @dev The verifier has the authority to confirm NFTs so ERC20's can be minted
    function onlyWithRole(bytes32 role) internal view {
        require(hasRole(role, _msgSender()), Errors.COB_INVALID_CALLER);
    }

    function onlyOwningTCO2(uint256 tokenId) internal view {
        address tokenOwner = ownerOf(tokenId);
        require(tokenOwner == _msgSender(), Errors.COB_NOT_BATCH_OWNER);
        require(
            IToucanContractRegistry(contractRegistry).isValidERC20(tokenOwner),
            Errors.COB_INVALID_BATCH_OWNER
        );
    }

    // ------------------------
    //      Admin functions
    // ------------------------

    /// @notice Emergency function to disable contract's core functionality
    /// @dev    wraps _pause(), only Admin
    function pause() external virtual onlyBy(contractRegistry, owner()) {
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() external virtual onlyBy(contractRegistry, owner()) {
        _unpause();
    }

    function setToucanContractRegistry(address _address)
        external
        virtual
        onlyOwner
    {
        contractRegistry = _address;
    }

    function setSupportedRegistry(string memory registry, bool isSupported)
        external
        onlyOwner
    {
        require(
            supportedRegistries[registry] != isSupported,
            Errors.COB_ALREADY_SUPPORTED
        );
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
    /// @param tokenId The tokenId of the batch
    /// @param newStatus The new status to set
    function setStatusForDetokenizationOrRetirement(
        uint256 tokenId,
        BatchStatus newStatus
    ) external virtual override {
        onlyOwningTCO2(tokenId);
        BatchStatus currentStatus = nftList[tokenId].status;
        // Only valid transition to a requested status is from a confirmed batch
        if (
            newStatus == BatchStatus.DetokenizationRequested ||
            newStatus == BatchStatus.RetirementRequested
        ) {
            require(
                currentStatus == BatchStatus.Confirmed,
                Errors.COB_INVALID_NEW_STATUS
            );
            // Only valid transition to a finalized status is from a requested status
        } else if (newStatus == BatchStatus.DetokenizationFinalized) {
            require(
                currentStatus == BatchStatus.DetokenizationRequested,
                Errors.COB_INVALID_NEW_STATUS
            );
        } else if (newStatus == BatchStatus.RetirementFinalized) {
            require(
                currentStatus == BatchStatus.RetirementRequested,
                Errors.COB_INVALID_NEW_STATUS
            );
            // Only valid transition to a confirmed status is from a requested status
        } else if (newStatus == BatchStatus.Confirmed) {
            require(
                currentStatus == BatchStatus.DetokenizationRequested ||
                    currentStatus == BatchStatus.RetirementRequested,
                Errors.COB_INVALID_NEW_STATUS
            );
        } else {
            revert(Errors.COB_INVALID_NEW_STATUS);
        }
        _updateStatus(tokenId, newStatus);
    }

    /// @notice Function to approve a Batch-NFT after validation.
    /// Fractionalization requires status Confirmed.
    /// @dev    This flow requires a previous linking with a `projectVintageTokenId`.
    function confirmBatch(uint256 tokenId) external virtual whenNotPaused {
        onlyWithRole(VERIFIER_ROLE);
        _confirmBatch(tokenId);
    }

    /// @dev    Internal function that is required a previous linking with a `projectVintageTokenId`.
    function _confirmBatch(uint256 _tokenId) internal {
        require(_exists(_tokenId), Errors.COB_NOT_EXISTS);
        require(
            nftList[_tokenId].status == BatchStatus.Pending,
            Errors.COB_INVALID_STATUS
        );
        require(
            nftList[_tokenId].projectVintageTokenId != 0,
            Errors.COB_MISSING_VINTAGE
        );
        require(
            serialNumberApproved[nftList[_tokenId].serialNumber] == false,
            Errors.COB_ALREADY_APPROVED
        );
        /// @dev setting serialnumber as unique after confirmation
        serialNumberApproved[nftList[_tokenId].serialNumber] = true;
        _updateStatus(_tokenId, BatchStatus.Confirmed);
    }

    /// @notice Function to reject Batch-NFTs, e.g. if the serial number entered is incorrect.
    function rejectRetirement(uint256 tokenId) public virtual whenNotPaused {
        onlyWithRole(VERIFIER_ROLE);
        require(
            nftList[tokenId].status == BatchStatus.Pending,
            Errors.COB_NOT_PENDING
        );
        /// @dev unsetting serialnumber with rejection
        serialNumberApproved[nftList[tokenId].serialNumber] = false;
        _updateStatus(tokenId, BatchStatus.Rejected);
    }

    /// @notice Function to reject Batch-NFTs, including a reason to be displayed to the user.
    function rejectWithComment(uint256 tokenId, string memory comment)
        external
        virtual
        whenNotPaused
    {
        onlyWithRole(VERIFIER_ROLE);
        rejectRetirement(tokenId);
        addComment(tokenId, comment);
    }

    /// @dev admin function to reject a previously approved batch
    /// Requires that the Batch-NFT has not been fractionalized yet
    function rejectApprovedWithComment(uint256 tokenId, string memory comment)
        external
        virtual
        onlyOwner
        whenNotPaused
    {
        require(
            nftList[tokenId].status == BatchStatus.Confirmed,
            Errors.COB_NOT_CONFIRMED
        );
        require(
            IToucanContractRegistry(contractRegistry).isValidERC20(
                ownerOf(tokenId)
            ) == false,
            Errors.COB_ALREADY_FRACTIONALIZED
        );
        _updateStatus(tokenId, BatchStatus.Rejected);
        addComment(tokenId, comment);
    }

    /// @notice Set batches back to pending after a rejection. This can
    /// be useful if there was an issue unrelated to the on-chain data of the
    /// batch, e.g. the batch was incorrectly rejected.
    function setToPending(uint256 tokenId) external virtual whenNotPaused {
        onlyWithRole(VERIFIER_ROLE);
        require(
            nftList[tokenId].status == BatchStatus.Rejected,
            Errors.COB_NOT_REJECTED
        );
        _updateStatus(tokenId, BatchStatus.Pending);
    }

    /// @dev Function for alternative flow where Batch-NFT approval is done separately.
    function linkWithVintage(uint256 tokenId, uint256 projectVintageTokenId)
        external
        virtual
        whenNotPaused
    {
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

    /// @dev Function for main approval flow, which requires passing a `projectVintageTokenId`.
    function confirmBatchWithVintage(
        uint256 tokenId,
        uint256 projectVintageTokenId
    ) external virtual whenNotPaused {
        onlyWithRole(VERIFIER_ROLE);
        // We don't want this to be a "backdoor" for modifying the vintage; it
        // could be insecure or allow accidents to happen, and it would also
        // result in BatchLinkedWithVintage being emitted more than once per
        // batch.
        require(
            nftList[tokenId].projectVintageTokenId == 0,
            Errors.COB_VINTAGE_ALREADY_SET
        );
        _linkWithVintage(tokenId, projectVintageTokenId);
        _confirmBatch(tokenId);
    }

    /// @dev Function to remove uniqueness for previously set serialnumbers.
    /// N.B. even though (technically speaking) calling this to complete the
    /// upgrade to a fixed contract is the responsibility of the contract's
    /// owner (deployer), in practice that is a multi-sig even before upgrade,
    /// and unsetting a bunch of serials via multi-sig is not practical.
    /// So instead we allow the verifiers to do it.
    function unsetSerialNumber(string memory serialNumber) external {
        onlyWithRole(VERIFIER_ROLE);
        serialNumberApproved[serialNumber] = false;
    }

    // ----------------------------------
    //  (Semi-)Permissionless functions
    // ----------------------------------

    /// @notice     Permissionlessly mint empty BatchNFTs
    /// Entry point to the carbon bridging process.
    /// @dev        To be updated by NFT owner after serial number has been provided
    /// @param to   The address the NFT should be minted to. This should be the user.
    /// @return     The token ID of the newly minted NFT
    function mintEmptyBatch(address to)
        external
        virtual
        whenNotPaused
        returns (uint256)
    {
        return _mintEmptyBatch(to, to);
    }

    /// @notice Permissionlessly mint empty BatchNFTs
    /// Entry point to the carbon bridging process.
    /// @dev To be updated by NFT owner after serial number has been provided
    /// @param to The address the NFT should be minted to. This should be the user
    /// but can also be the CarbonOffsetBatches contract itself in case the batch NFT
    /// is held temporarily by the contract before fractionalization (see tokenize()).
    /// @param onBehalfOf The address of user on behalf of whom the batch is minted
    /// @return The token ID of the newly minted NFT
    function _mintEmptyBatch(address to, address onBehalfOf)
        internal
        returns (uint256)
    {
        uint256 newItemId = batchTokenCounter;
        unchecked {
            ++newItemId;
        }
        batchTokenCounter = newItemId;

        _safeMint(to, newItemId);
        nftList[newItemId].status = BatchStatus.Pending;

        emit BatchMinted(onBehalfOf, newItemId);
        return newItemId;
    }

    /// @notice Updates BatchNFT after Serialnumber has been verified
    /// @dev    Data is usually inserted by the user (NFT owner) via the UI
    /// @param tokenId the Batch-NFT
    /// @param serialNumber the serial number received from the registry/credit cancellation
    /// @param quantity quantity in tCO2e
    /// @param uri optional tokenURI with additional information
    function updateBatchWithData(
        uint256 tokenId,
        string memory serialNumber,
        uint256 quantity,
        string memory uri
    ) external virtual whenNotPaused {
        require(
            ownerOf(tokenId) == _msgSender() ||
                hasRole(VERIFIER_ROLE, _msgSender()),
            Errors.COB_NOT_VERIFIER
        );
        _updateBatchWithData(tokenId, serialNumber, quantity, uri);
    }

    /// @notice Internal function that updates BatchNFT after serial number has been verified
    function _updateBatchWithData(
        uint256 tokenId,
        string memory serialNumber,
        uint256 quantity,
        string memory uri
    ) internal {
        BatchStatus status = nftList[tokenId].status;
        require(status == BatchStatus.Pending, Errors.COB_INVALID_STATUS);
        require(
            serialNumberApproved[serialNumber] == false,
            Errors.COB_ALREADY_APPROVED
        );
        nftList[tokenId].serialNumber = serialNumber;
        nftList[tokenId].quantity = quantity;

        if (!uri.equals(nftList[tokenId].uri)) {
            nftList[tokenId].uri = uri;
        }

        emit BatchUpdated(tokenId, serialNumber, quantity);
    }

    /// @dev Convenience function to only update serial number and quantity and not the serial/URI
    /// @param newSerialNumber the serial number received from the registry/credit cancellation
    /// @param newQuantity quantity in tCO2e
    function setSerialandQuantity(
        uint256 tokenId,
        string memory newSerialNumber,
        uint256 newQuantity
    ) external virtual whenNotPaused {
        require(
            ownerOf(tokenId) == _msgSender() ||
                hasRole(VERIFIER_ROLE, _msgSender()),
            Errors.COB_NOT_VERIFIER
        );
        require(
            nftList[tokenId].status == BatchStatus.Pending,
            Errors.COB_INVALID_STATUS
        );
        require(
            serialNumberApproved[newSerialNumber] == false,
            Errors.COB_ALREADY_APPROVED
        );
        nftList[tokenId].serialNumber = newSerialNumber;
        nftList[tokenId].quantity = newQuantity;

        emit BatchUpdated(tokenId, newSerialNumber, newQuantity);
    }

    /// @notice Returns just the confirmation (approval) status of Batch-NFT
    function getConfirmationStatus(uint256 tokenId)
        external
        view
        virtual
        override
        returns (BatchStatus)
    {
        return nftList[tokenId].status;
    }

    /// @notice Returns all data from Batch-NFT
    /// @dev Used in TCO2 contract's receive hook `onERC721Received`
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
        return (
            nftList[tokenId].projectVintageTokenId,
            nftList[tokenId].quantity,
            nftList[tokenId].status
        );
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
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            Errors.COB_TRANSFER_NOT_APPROVED
        );
        safeTransferFrom(from, to, tokenId, '');
    }

    /// @notice Function that automatically converts Batch-NFT to TCO2 (ERC20)
    /// @dev Queries the factory to find the corresponding TCO2 contract
    /// Fractionalization happens via receive hook on `safeTransferFrom`
    function fractionalize(uint256 tokenId) external virtual {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            Errors.COB_TRANSFER_NOT_APPROVED
        );
        address tco2 = _getTCO2ForBatchTokenId(tokenId);
        // Fractionalize by transferring the batch NFT to the TCO2 contract.
        safeTransferFrom(_msgSender(), tco2, tokenId, '');
    }

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

        return ToucanCarbonOffsetsFactory(tco2Factory).pvIdtoERC20(pvId);
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

    function setBaseURI(string memory gateway) external virtual onlyOwner {
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
        require(_exists(tokenId), Errors.COB_NOT_EXISTS);

        string memory uri = nftList[tokenId].uri;
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return uri;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(uri).length > 0) {
            return string(abi.encodePacked(base, uri));
        }

        return super.tokenURI(tokenId);
    }

    /// @dev Utilized here in order to disable transfers when paused
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), Errors.COB_PAUSED_CONTRACT);
    }

    /// @notice Append a comment to a Batch-NFT
    /// @dev Don't allow the contract owner to comment.  When the contract owner
    /// can also be a verifier they should add them as a verifier first; this
    /// should prevent accidental comments from the wrong account.
    function addComment(uint256 tokenId, string memory comment) public virtual {
        require(
            hasRole(VERIFIER_ROLE, _msgSender()) ||
                _msgSender() == ownerOf(tokenId) ||
                _msgSender() == owner(),
            Errors.COB_INVALID_CALLER
        );
        require(_exists(tokenId), Errors.COB_NOT_EXISTS);
        nftList[tokenId].comments.push() = comment;
        nftList[tokenId].commentAuthors.push() = _msgSender();
        emit BatchComment(
            tokenId,
            nftList[tokenId].comments.length,
            _msgSender(),
            comment
        );
    }

    /**
     * @notice This function allows external APIs to tokenize their carbon credits
     * @param recipient Recipient of the tokens
     * @param serialNumber Serial number of the carbon credits to be tokenized
     * @param quantity Quantity to be tokenized in 1e18 format
     * @param projectVintageTokenId Project vintage token ID
     */
    function tokenize(
        address recipient,
        string calldata serialNumber,
        uint256 quantity,
        uint256 projectVintageTokenId
    ) external whenNotPaused {
        onlyWithRole(TOKENIZER_ROLE);
        // Prepare and confirm batch
        uint256 tokenId = _mintEmptyBatch(address(this), recipient);
        _updateBatchWithData(tokenId, serialNumber, quantity, '');
        _linkWithVintage(tokenId, projectVintageTokenId);
        _confirmBatch(tokenId);

        // Check existing TCO2 balance; to be used at the end
        // to send the exact TCO2 needed to the recipient.
        address tco2 = _getTCO2ForBatchTokenId(tokenId);
        require(tco2 != address(0), Errors.COB_TCO2_NOT_FOUND);
        string memory registry = IToucanCarbonOffsets(tco2).standardRegistry();
        require(
            supportedRegistries[registry],
            Errors.COB_REGISTRY_NOT_SUPPORTED
        );
        uint256 balanceBefore = IERC20Upgradeable(tco2).balanceOf(
            address(this)
        );

        // Fractionalize by transferring the batch NFT to the TCO2 contract.
        _safeTransfer(address(this), tco2, tokenId, '');

        // Transfer minted TCO2s to recipient.
        uint256 balanceAfter = IERC20Upgradeable(tco2).balanceOf(address(this));
        uint256 amount = balanceAfter - balanceBefore;
        require(amount != 0, Errors.COB_NO_TCO2_MINTED);
        IERC20Upgradeable(tco2).safeTransfer(recipient, amount);
        emit Tokenized(tokenId, tco2, recipient, amount);
    }

    function onERC721Received(
        address, /* operator */
        address from, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external view whenNotPaused returns (bytes4) {
        // This hook is only used by the contract to mint batch NFTs that
        // can be tokenized on behalf of end users.
        require(from == address(0), Errors.COB_ONLY_MINTS);
        return this.onERC721Received.selector;
    }
}
