// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './IToucanContractRegistry.sol';
import './ICarbonOffsetBatches.sol';
import './ToucanCarbonOffsetsFactory.sol';
import './CarbonOffsetBatchesStorage.sol';
import './libraries/ProjectVintageUtils.sol';
import './libraries/Modifiers.sol';

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

    bytes32 public constant VERIFIER_ROLE = keccak256('VERIFIER_ROLE');

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    /// @dev Returns the current version of the smart contract
    function version() public pure returns (string memory) {
        return '1.2.0';
    }

    function initialize(address _contractRegistry) public virtual initializer {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'Toucan Protocol: Carbon Offset Batches',
            'TOUCAN-COB'
        );
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        contractRegistry = _contractRegistry;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    /// @dev wraps _pause(), only Admin
    function pause() public virtual onlyBy(contractRegistry, owner()) {
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() public virtual onlyBy(contractRegistry, owner()) {
        _unpause();
    }

    function setToucanContractRegistry(address _address)
        public
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

    function updateStatus(uint256 tokenId, RetirementStatus newStatus)
        internal
        virtual
    {
        nftList[tokenId].status = newStatus;
        emit BatchStatusUpdate(tokenId, newStatus);
    }

    /// @dev To confirm that claim about retirement is valid
    /// fractionalization requires confirmation
    function confirmRetirement(uint256 tokenId)
        public
        virtual
        onlyVerifier
        whenNotPaused
    {
        require(
            _exists(tokenId),
            'ERC721: approved query for nonexistent token'
        );
        require(
            nftList[tokenId].status != RetirementStatus.Confirmed,
            'Batch retirement is already confirmed'
        );
        require(
            nftList[tokenId].projectVintageTokenId != 0,
            'Cannot retire batch without project vintage'
        );
        require(
            serialNumberExist[nftList[tokenId].serialNumber] == false,
            'Serialnumber has already been approved'
        );
        /// @dev setting serialnumber as unique after confirmation
        serialNumberExist[nftList[tokenId].serialNumber] = true;
        updateStatus(tokenId, RetirementStatus.Confirmed);
    }

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
        serialNumberExist[nftList[tokenId].serialNumber] = false;
        updateStatus(tokenId, RetirementStatus.Rejected);
    }

    function rejectWithComment(uint256 tokenId, string memory comment)
        public
        virtual
        onlyVerifier
        whenNotPaused
    {
        rejectRetirement(tokenId);
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

    function linkWithVintage(uint256 tokenId, uint256 projectVintageTokenId)
        public
        virtual
        onlyVerifier
        whenNotPaused
    {
        checkProjectVintageTokenExists(contractRegistry, projectVintageTokenId);
        nftList[tokenId].projectVintageTokenId = projectVintageTokenId;
        emit BatchLinkedWithVintage(tokenId, projectVintageTokenId);
    }

    function confirmRetirementWithVintage(
        uint256 tokenId,
        uint256 projectVintageTokenId
    ) public virtual onlyVerifier whenNotPaused {
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
        linkWithVintage(tokenId, projectVintageTokenId);
        confirmRetirement(tokenId);
    }

    /// @dev Function to remove uniqueness for previously set serialnumbers.
    /// N.B. even though (technically speaking) calling this to complete the
    /// upgrade to a fixed contract is the responsibility of the contract's
    /// owner (deployer), in practice that is a multi-sig even before upgrade,
    /// and unsetting a bunch of serials via multi-sig is not practical.
    /// So instead we allow the verifiers to do it.
    function unsetSerialNumber(string memory serialNumber) public onlyVerifier {
        serialNumberExist[serialNumber] = false;
    }

    // ----------------------------------
    //  (Semi-)Permissionless functions
    // ----------------------------------

    /// @notice Permissionlessly mint empty BatchNFTs
    /// @dev    To be updated by NFT owner after serial number has been provided
    function mintEmptyBatch(address to) external virtual whenNotPaused {
        batchTokenCounter++;
        uint256 newItemId = batchTokenCounter;
        _safeMint(to, newItemId);
        nftList[newItemId].status = RetirementStatus.Pending;

        emit BatchMinted(to, newItemId);
    }

    /// @dev  Updates BatchNFT after Serialnumber has been verified
    /// Data is inserted by the NFT owner or verifier
    function updateBatchWithData(
        uint256 tokenId,
        string memory serialNumber,
        uint256 quantity,
        string memory uri
    ) public virtual whenNotPaused {
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
            serialNumberExist[serialNumber] == false,
            'Serialnumber has already been approved'
        );
        nftList[tokenId].serialNumber = serialNumber;
        nftList[tokenId].quantity = quantity;

        // Make sure metadata does not exist twice
        if (!strcmp(uri, nftList[tokenId].uri)) {
            require(URIs[uri] == false, 'Error: uri already exists');
            nftList[tokenId].uri = uri;
            URIs[uri] = true;
        }

        if (nftList[tokenId].status == RetirementStatus.Rejected) {
            updateStatus(tokenId, RetirementStatus.Pending);
        }

        emit BatchUpdated(tokenId, serialNumber, quantity);
    }

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
            serialNumberExist[newSerialNumber] == false,
            'Serialnumber has already been approved'
        );
        nftList[tokenId].serialNumber = newSerialNumber;
        nftList[tokenId].quantity = newQuantity;

        emit BatchUpdated(tokenId, newSerialNumber, newQuantity);
    }

    function getConfirmationStatus(uint256 tokenId)
        external
        view
        virtual
        override
        returns (RetirementStatus)
    {
        return nftList[tokenId].status;
    }

    // Used by onERC721Received when batch is transferred to TCO2 contract
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
        public
        view
        virtual
        returns (string[] memory, address[] memory)
    {
        return (nftList[tokenId].comments, nftList[tokenId].commentAuthors);
    }

    /// @dev here for debugging/mock purposes. safeTransferFrom(...) is error prone with ethers.js
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            'ERC721: transfer caller is not owner nor approved'
        );
        safeTransferFrom(from, to, tokenId, '');
    }

    /// @notice Function that automatically converts to ERC20s via corresponding contract
    function fractionalize(uint256 tokenId) external virtual {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            'ERC721: transfer caller is not owner nor approved'
        );
        require(
            nftList[tokenId].status == RetirementStatus.Confirmed,
            'Error: cannot fractionalize before confirmation'
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

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     * based on the ERC721URIStorage implementation
     */
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

    // Implemented in order to disable transfers when paused
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), 'ERC20Pausable: token transfer while paused');
    }

    /// @notice Append a comment to a batch.
    /// @dev Don't allow the contract owner to comment.  When the contract owner
    /// can also be a verifier they should add them as a verifier first; this
    /// should prevent accidental comments from the wrong account.
    function addComment(uint256 tokenId, string memory comment) public virtual {
        require(
            hasRole(VERIFIER_ROLE, _msgSender()) ||
                _msgSender() == ownerOf(tokenId),
            'Only the batch owner and verifiers can comment'
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
