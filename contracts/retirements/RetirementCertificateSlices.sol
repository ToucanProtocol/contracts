// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import './RetirementCertificateSlicesStorage.sol';
import '../interfaces/IRetirementCertificateSlices.sol';
import '../libraries/Strings.sol';
import '../bases/RoleInitializer.sol';

/// @notice The `RetirementCertificateSlices.sol` contract lets users mint NFTs that
/// represent a slice of a retirement certificate.
/// @dev The amount of carbon is denominated in the 18-decimal form
contract RetirementCertificateSlices is
    IRetirementCertificateSlices,
    ERC721Upgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    RoleInitializer,
    RetirementCertificateSlicesStorage
{
    // ----------------------------------------
    //      Libraries
    // ----------------------------------------

    using Strings for string;
    using Strings for uint256;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @dev All roles related to accessing this contract
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event BaseURISet(string baseURI);

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory baseURI_,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external initializer {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'Toucan Protocol: Retirement Certificate Slices for Tokenized Carbon Offsets',
            'TOUCAN-CERT-SLICE'
        );
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();
        __RoleInitializer_init_unchained(accounts, roles);

        baseURI = baseURI_;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC721Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ------------------------
    //      Admin functions
    // ------------------------

    /// @notice Set the base URI for all token IDs.
    /// NOTE: If the given URI doesn't end with a slash, it will be added automatically.
    /// @param baseURI_ The base URI to set.
    function setBaseURI(string memory baseURI_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        baseURI = (bytes(baseURI_).length != 0 &&
            bytes(baseURI_)[bytes(baseURI_).length - 1] != '/')
            ? string.concat(baseURI_, '/')
            : baseURI_;
        emit BaseURISet(baseURI_);
    }

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), callable only by pausers
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Emergency function to re-enable contract's core functionality after being paused
    /// @dev wraps _unpause(), callable only by pausers
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Mint a slice of a retirement certificate.
    /// @dev Only the retirement certificate slicer can call this function.
    /// @param sliceData The data of the slice to mint.
    /// @return The id of the minted slice NFT.
    function mintSlice(
        address, /* caller */
        SliceData calldata sliceData
    )
        external
        virtual
        nonReentrant
        whenNotPaused
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        return _mintSlice(sliceData);
    }

    function _mintSlice(SliceData calldata sliceData)
        internal
        returns (uint256)
    {
        require(sliceData.amount != 0, 'Amount must be greater than 0');
        uint256 newItemId = _tokenIds;
        unchecked {
            ++newItemId;
        }
        _tokenIds = newItemId;

        slices[newItemId] = sliceData;

        _safeMint(sliceData.beneficiary, newItemId);
        return newItemId;
    }

    // ----------------------------------
    //     Permissionless functions
    // ----------------------------------

    /// @notice Get the URI for a token ID. Returns an empty string if no URI is set.
    /// @param tokenId The id of the NFT to get the URI for.
    /// @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    /// based on the ERC721URIStorage implementation
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), 'Non-existent token id');
        string memory _tokenURI = slices[tokenId].tokenURI;
        // If there is no base URI, return the token URI.
        // If both are not set, return an empty string.
        if (bytes(baseURI).length == 0) return _tokenURI;
        // If both are set, concatenate the baseURI and tokenURI
        if (bytes(_tokenURI).length != 0)
            return string.concat(baseURI, _tokenURI);

        // If there is a baseURI but no tokenURI, concatenate the tokenID to
        // the baseURI.
        return string.concat(baseURI, tokenId.toString());
    }
}
