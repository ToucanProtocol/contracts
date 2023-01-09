// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IToucanContractRegistry.sol';
import './interfaces/ICarbonOffsetBatches.sol';
import './ToucanCarbonOffsetsFactory.sol';
import './CarbonOffsetBatchesStorage.sol';
import './libraries/ProjectVintageUtils.sol';
import './libraries/Modifiers.sol';

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

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev auto-created getter VERSION() returns the current version of the smart contract
    string public constant VERSION = '1.3.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;
    bytes32 public constant VERIFIER_ROLE = keccak256('VERIFIER_ROLE');

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
    event BatchStatusUpdate(uint256 tokenId, RetirementStatus status);

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

    /// @dev The verifier has the authority to confirm NFTs so ERC20's can be minted
    modifier onlyVerifier() {
        require(
            hasRole(VERIFIER_ROLE, _msgSender()),
            'Error: caller is not the verifier'
        );
        _;
    }

    /// @dev internal helper function to set the status and emit an event
    function updateStatus(uint256 tokenId, RetirementStatus newStatus)
        internal
        virtual
    {
        nftList[tokenId].status = newStatus;
        emit BatchStatusUpdate(tokenId, newStatus);
    }

    /// @notice Function to approve a Batch-NFT after validation.
    /// Fractionalization requires status Confirmed.
    /// @dev    This flow requires a previous linking with a `projectVintageTokenId`.
    function confirmRetirement(uint256 tokenId)
        external
        virtual
        onlyVerifier
        whenNotPaused
    {
        _confirmRetirement(tokenId);
    }

    /// @dev    Internal function that is required a previous linking with a `projectVintageTokenId`.
    function _confirmRetirement(uint256 _tokenId) internal {
        require(
            _exists(_tokenId),
            'ERC721: approved query for nonexistent token'
        );
        require(
            nftList[_tokenId].status != RetirementStatus.Confirmed,
            'Batch retirement is already confirmed'
        );
        require(
            nftList[_tokenId].projectVintageTokenId != 0,
            'Cannot retire batch without project vintage'
        );
        require(
            serialNumberApproved[nftList[_tokenId].serialNumber] == false,
            'Serialnumber has already been approved'
        );
        /// @dev setting serialnumber as unique after confirmation
        serialNumberApproved[nftList[_tokenId].serialNumber] = true;
        updateStatus(_tokenId, RetirementStatus.Confirmed);
    }

    /// @notice Function to reject Batch-NFTs, e.g. if the serial number entered is incorrect.
    function rejectRetirement(uint256 tokenId)
        public
        virtual
        onlyVerifier
        whenNotPaused
    {
        require(
            nftList[tokenId].status == RetirementStatus.Pending,
            'Batch must be in pending state to be rejected'
        );
        /// @dev unsetting serialnumber with rejection
        serialNumberApproved[nftList[tokenId].serialNumber] = false;
        updateStatus(tokenId, RetirementStatus.Rejected);
    }

    /// @notice Function to reject Batch-NFTs, including a reason to be displayed to the user.
    function rejectWithComment(uint256 tokenId, string memory comment)
        external
        virtual
        onlyVerifier
        whenNotPaused
    {
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
            nftList[tokenId].status == RetirementStatus.Confirmed,
            'Batch must be in confirmed state to be rejected'
        );
        require(
            IToucanContractRegistry(contractRegistry).checkERC20(
                ownerOf(tokenId)
            ) == false,
            'Batch has already been fractionalized'
        );
        updateStatus(tokenId, RetirementStatus.Rejected);
        addComment(tokenId, comment);
    }

    /// @notice Set batches back to pending after a rejection. This can
    /// be useful if there was an issue unrelated to the on-chain data of the
    /// batch, e.g. the batch was incorrectly rejected.
    function setToPending(uint256 tokenId)
        external
        virtual
        onlyVerifier
        whenNotPaused
    {
        require(
            nftList[tokenId].status == RetirementStatus.Rejected,
            'Can only reset rejected batches to pending'
        );
        updateStatus(tokenId, RetirementStatus.Pending);
    }

    /// @dev Function for alternative flow where Batch-NFT approval is done separately.
    function linkWithVintage(uint256 tokenId, uint256 projectVintageTokenId)
        external
        virtual
        onlyVerifier
        whenNotPaused
    {
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
    function confirmRetirementWithVintage(
        uint256 tokenId,
        uint256 projectVintageTokenId
    ) external virtual onlyVerifier whenNotPaused {
        require(
            nftList[tokenId].status != RetirementStatus.Confirmed,
            'Batch retirement is already confirmed'
        );
        // We don't want this to be a "backdoor" for modifying the vintage; it
        // could be insecure or allow accidents to happen, and it would also
        // result in BatchLinkedWithVintage being emitted more than once per
        // batch.
        require(
            nftList[tokenId].projectVintageTokenId == 0,
            'Vintage is already set and cannot be changed; use confirmRetirement instead'
        );
        _linkWithVintage(tokenId, projectVintageTokenId);
        _confirmRetirement(tokenId);
    }

    /// @dev Function to remove uniqueness for previously set serialnumbers.
    /// N.B. even though (technically speaking) calling this to complete the
    /// upgrade to a fixed contract is the responsibility of the contract's
    /// owner (deployer), in practice that is a multi-sig even before upgrade,
    /// and unsetting a bunch of serials via multi-sig is not practical.
    /// So instead we allow the verifiers to do it.
    function unsetSerialNumber(string memory serialNumber)
        external
        onlyVerifier
    {
        serialNumberApproved[serialNumber] = false;
    }

    // ----------------------------------
    //  (Semi-)Permissionless functions
    // ----------------------------------

    /// @notice     Permissionlessly mint empty BatchNFTs
    /// Entry point to the carbon bridging process.
    /// @dev        To be updated by NFT owner after serial number has been provided
    /// @param to   The address the NFT should be minted to. This should be the user.
    function mintEmptyBatch(address to) public virtual whenNotPaused {
        uint256 newItemId = batchTokenCounter;
        unchecked {
            ++newItemId;
        }
        batchTokenCounter = newItemId;

        _safeMint(to, newItemId);
        nftList[newItemId].status = RetirementStatus.Pending;

        emit BatchMinted(to, newItemId);
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
            'Error: update only by owner or verifier'
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
        RetirementStatus status = nftList[tokenId].status;
        require(
            status != RetirementStatus.Confirmed,
            'Error: cannot change data after confirmation'
        );
        require(
            serialNumberApproved[serialNumber] == false,
            'Serialnumber has already been approved'
        );
        nftList[tokenId].serialNumber = serialNumber;
        nftList[tokenId].quantity = quantity;

        if (!strcmp(uri, nftList[tokenId].uri)) {
            nftList[tokenId].uri = uri;
        }

        if (status == RetirementStatus.Rejected) {
            updateStatus(tokenId, RetirementStatus.Pending);
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
            'Error: update only by owner or verifier'
        );
        require(
            nftList[tokenId].status != RetirementStatus.Confirmed,
            'Error: cannot change data after confirmation'
        );
        require(
            serialNumberApproved[newSerialNumber] == false,
            'Serialnumber has already been approved'
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
        returns (RetirementStatus)
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
            RetirementStatus
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
            'ERC721: transfer caller is not owner nor approved'
        );
        safeTransferFrom(from, to, tokenId, '');
    }

    /// @notice Function that automatically converts Batch-NFT to TCO2 (ERC20)
    /// @dev Queries the factory to find the corresponding TCO2 contract
    /// Fractionalization happens via receive hook on `safeTransferFrom`
    function fractionalize(uint256 tokenId) external virtual {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            'ERC721: transfer caller is not owner nor approved'
        );

        address ERC20Factory = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsFactoryAddress();
        uint256 pvId = nftList[tokenId].projectVintageTokenId;
        address pvERC20 = ToucanCarbonOffsetsFactory(ERC20Factory).pvIdtoERC20(
            pvId
        );

        safeTransferFrom(_msgSender(), pvERC20, tokenId, '');
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
        require(
            _exists(tokenId),
            'ERC721URIStorage: URI query for nonexistent token'
        );

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

        require(!paused(), 'ERC20Pausable: token transfer while paused');
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
            'Only the batch owner, contract owner and verifiers can comment'
        );
        require(_exists(tokenId), 'Cannot comment on non-existent batch');
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
     * @notice This function allows external APIs to tokenize their carbon credits to validated NFTs
     * @param to  Address to empty NFT is minted to
     * @param serialNumber  serialNumber recieved from the registry/credit cancellation
     * @param quantity  quantity in tC02e
     * @param uri  optional tokenURI information with additional data
     * @param projectVintageTokenId Project Vintage Token ID
     */
    function tokenize(
        address to,
        string calldata serialNumber,
        uint256 quantity,
        string calldata uri,
        uint256 projectVintageTokenId
    ) external virtual onlyVerifier whenNotPaused {
        mintEmptyBatch(to);
        _updateBatchWithData(batchTokenCounter, serialNumber, quantity, uri);
        _linkWithVintage(batchTokenCounter, projectVintageTokenId);
        _confirmRetirement(batchTokenCounter);
    }

    // -----------------------------
    //      Helper Functions
    // -----------------------------

    /// @dev internal helper for string comparison
    function strcmp(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return memcmp(bytes(a), bytes(b));
    }

    /// @dev internal helper for string comparison
    function memcmp(bytes memory a, bytes memory b)
        internal
        pure
        returns (bool)
    {
        return (a.length == b.length) && (keccak256(a) == keccak256(b));
    }
}
