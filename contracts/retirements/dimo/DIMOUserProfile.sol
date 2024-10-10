// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';

import '../../bases/RoleInitializer.sol';
import './interfaces/IDIMOCostBasisSales.sol';
import './interfaces/IDIMOUserProfile.sol';
import './DIMOUserProfileStorage.sol';

contract DIMOUserProfile is
    IDIMOUserProfile,
    ERC721Upgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    RoleInitializer,
    DIMOUserProfileStorage
{
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
    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event AllowedCallerSet(address caller, bool allowed);
    event ThresholdSet(uint256 index, uint256 threshold);
    event TokenURISet(uint256 index, string tokenURI);
    event BaseURISet(string baseURI);
    event DIMOCostBasisSalesSet(address costBasisSalesAddress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(
        string memory baseURI_,
        address costBasisSales,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external initializer {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'DIMO Better Together Carbon Retirements',
            'DCO2R'
        );
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();
        __RoleInitializer_init_unchained(accounts, roles);

        baseURI = baseURI_;
        dimoCostBasisSales = costBasisSales;
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
        override(
            AccessControlUpgradeable,
            ERC721Upgradeable,
            IERC165Upgradeable
        )
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

    /// @notice Set the address of the DIMOCostBasisSales contract
    /// @param dimoCostBasisSales_ The address of the DIMOCostBasisSales contract
    function setDIMOCostBasisSales(address dimoCostBasisSales_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        dimoCostBasisSales = dimoCostBasisSales_;
        emit DIMOCostBasisSalesSet(dimoCostBasisSales_);
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

    /// @notice Set both tokenURIs and thresholds
    /// @param tokenURIs_ The token URIs to set
    /// @param thresholds_ The thresholds to set
    function setTokenURIsAndThresholds(
        string[] calldata tokenURIs_,
        uint256[] calldata thresholds_
    ) external onlyRole(MANAGER_ROLE) {
        require(tokenURIs_.length == thresholds_.length + 1, 'Length mismatch');
        _setTokenURIs(tokenURIs_);
        _setThresholds(thresholds_);
    }

    /// @notice Set only tokenURIs
    /// @param tokenURIs_ The token URIs to set
    function setTokenURIs(string[] calldata tokenURIs_)
        external
        onlyRole(MANAGER_ROLE)
    {
        require(tokenURIs_.length == _thresholds.length + 1, 'Length mismatch');
        _setTokenURIs(tokenURIs_);
    }

    /// @notice Set only thresholds
    /// @param thresholds_ The thresholds to set
    function setThresholds(uint256[] calldata thresholds_)
        external
        onlyRole(MANAGER_ROLE)
    {
        require(_tokenURIs.length == thresholds_.length + 1, 'Length mismatch');
        _setThresholds(thresholds_);
    }

    /// @notice Mint a new user profile NFT
    /// @param to The address to mint the NFT to
    /// @dev Only callable by minters
    function mint(address to) external onlyRole(MINTER_ROLE) returns (uint256) {
        _safeMint(to, ++_tokenIndex);
        return _tokenIndex;
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
        override
        returns (string memory)
    {
        require(_exists(tokenId), 'Non-existent token id');

        string memory tokenURI_ = _getTokenURIBasedOnTotalSold();

        return string.concat(baseURI, tokenURI_);
    }

    function tokenURIs() external view returns (string[] memory) {
        return _tokenURIs;
    }

    function thresholds() external view returns (uint256[] memory) {
        return _thresholds;
    }

    // ----------------------------------------
    //      Internal functions
    // ----------------------------------------

    function _setTokenURIs(string[] calldata tokenURIs_) internal {
        /// Unfortunately it's not possible yet to assign calldata dynamic arrays
        /// to storage via references so we have to set the underlying array values
        /// one by one.
        delete _tokenURIs;

        uint256 tokenURILen = tokenURIs_.length;
        for (uint256 i = 0; i < tokenURILen; ++i) {
            if (bytes(tokenURIs_[i]).length == 0) revert('Empty token URI');
            _tokenURIs.push(tokenURIs_[i]);
            emit TokenURISet(i, tokenURIs_[i]);
        }
    }

    function _setThresholds(uint256[] calldata thresholds_) internal {
        /// Unfortunately it's not possible yet to assign calldata dynamic arrays
        /// to storage via references so we have to set the underlying array values
        /// one by one.
        delete _thresholds;

        _thresholds.push(thresholds_[0]);
        emit ThresholdSet(0, thresholds_[0]);

        uint256 thresholdLen = thresholds_.length;
        for (uint256 i = 1; i < thresholdLen; ++i) {
            require(
                thresholds_[i] > thresholds_[i - 1],
                'Thresholds not sorted'
            );
            _thresholds.push(thresholds_[i]);
            emit ThresholdSet(i, thresholds_[i]);
        }
    }

    function _getTokenURIBasedOnTotalSold()
        internal
        view
        returns (string memory)
    {
        if (_tokenURIs.length == 0) return '';
        uint256 totalSold = IDIMOCostBasisSales(dimoCostBasisSales).totalSold();
        uint256 thresholdLen = _thresholds.length;
        for (uint256 i = 0; i < thresholdLen; ++i) {
            if (totalSold <= _thresholds[i]) return _tokenURIs[i];
        }
        return _tokenURIs[thresholdLen];
    }
}
