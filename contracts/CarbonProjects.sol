// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './CarbonProjectsStorage.sol';
import './interfaces/ICarbonProjects.sol';

/// @notice The CarbonProjects contract stores carbon project-specific data
/// The data is stored in structs via ERC721 tokens
/// Most contracts in the protocol query the data stored here
/// The attributes in the Project-NFTs are constant over all vintages of the project
/// @dev Each project can have up to n vintages, with data stored in the
/// `CarbonProjectVintages` contract. `vintageTokenId`s are mapped to `projectTokenId`s
/// via `pvToTokenId` in the vintage contract.
//slither-disable-next-line unprotected-upgrade
contract CarbonProjects is
    ICarbonProjects,
    CarbonProjectsStorage,
    ERC721Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    string public constant VERSION = '1.1.0';
    /// @dev All roles related to Access Control
    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event ProjectMinted(address receiver, uint256 tokenId);
    event ProjectUpdated(uint256 tokenId);
    event ProjectIdUpdated(uint256 tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize() external virtual initializer {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'Toucan Protocol: Carbon Projects',
            'TOUCAN-CP'
        );
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        /// @dev granting the deployer==owner the rights to grant other roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address) internal virtual override {
        _onlyOwner();
    }

    // ------------------------
    //      Admin functions
    // ------------------------
    /// @dev modifier that only lets the contract's owner and elected managers add/update/remove project data

    function _onlyBy(address _contract, address _owner) internal view {
        if (_contract != msg.sender && _owner != msg.sender) {
            revert CallerNotAllowed();
        }
    }

    function _onlyOwner() internal view {
        if (_msgSender() != owner()) {
            revert OnlyOwner();
        }
    }

    function _onlyManagers() internal view {
        if (!hasRole(MANAGER_ROLE, _msgSender()) && owner() != _msgSender()) {
            revert NotManagerOrOwner();
        }
    }

    function _tokenExists(uint256 _tokenId) internal view {
        if (!_exists(_tokenId)) {
            revert TokenDoesNotExist();
        }
    }

    function _notPaused() internal view {
        if (paused()) {
            revert ContractPaused();
        }
    }

    function pause() external virtual {
        _onlyBy(contractRegistry, owner());
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() external virtual {
        _onlyBy(contractRegistry, owner());
        _unpause();
    }

    function setToucanContractRegistry(address _address) external virtual {
        _onlyOwner();
        contractRegistry = _address;
    }

    /// @notice Adds a new carbon project along with attributes/data
    /// @dev Projects can be added by data-managers
    function addNewProject(address to, ProjectData calldata _projectData)
        external
        virtual
        override
        returns (uint256)
    {
        _notPaused();
        _onlyManagers();

        string memory projectId = _projectData.projectId;

        if (strcmp(projectId, '')) revert ProjectIdCannotBeEmpty();
        if (projectIds[projectId]) revert ProjectIdAlreadyExists();

        projectIds[projectId] = true;

        uint256 newItemId = projectTokenCounter;
        ++newItemId;
        ++totalSupply;

        projectTokenCounter = uint128(newItemId);

        validProjectTokenIds[newItemId] = true;

        _mint(to, newItemId);

        projectData[newItemId] = _projectData;

        emit ProjectMinted(to, newItemId);
        pidToTokenId[projectId] = newItemId;
        return newItemId;
    }

    /// @notice Updates and existing carbon project
    /// @dev Projects can be updated by data-managers
    function updateProject(uint256 tokenId, ProjectData calldata _projectData)
        external
        virtual
    {
        _notPaused();
        _onlyManagers();
        _tokenExists(tokenId);

        projectData[tokenId] = _projectData;

        emit ProjectUpdated(tokenId);
    }

    /// @dev Projects and their projectId's must be unique, changing them must be handled carefully
    function updateProjectId(uint256 tokenId, string calldata newProjectId)
        external
        virtual
    {
        _notPaused();
        _onlyManagers();
        _tokenExists(tokenId);
        if (projectIds[newProjectId]) revert ProjectIdAlreadyExists();

        ProjectData storage pData = projectData[tokenId];

        string memory oldProjectId = pData.projectId;
        projectIds[oldProjectId] = false;

        pData.projectId = newProjectId;
        projectIds[newProjectId] = true;

        emit ProjectIdUpdated(tokenId);
    }

    /// @dev Removes a project and corresponding data, sets projectTokenId invalid
    function removeProject(uint256 projectTokenId) external virtual {
        _notPaused();
        _onlyManagers();
        delete projectData[projectTokenId];
        /// @dev set projectTokenId to invalid
        --totalSupply;
        validProjectTokenIds[projectTokenId] = false;
    }

    /// @dev Returns the global project-id, for example'VCS-1418'
    function getProjectId(uint256 tokenId)
        external
        view
        virtual
        override
        returns (string memory)
    {
        return projectData[tokenId].projectId;
    }

    /// @dev Function used by the utility function `checkProjectTokenExists`
    function isValidProjectTokenId(uint256 projectTokenId)
        external
        view
        virtual
        override
        returns (bool)
    {
        return validProjectTokenIds[projectTokenId];
    }

    /// @dev retrieve all data from ProjectData struct
    function getProjectDataByTokenId(uint256 tokenId)
        external
        view
        virtual
        override
        returns (ProjectData memory)
    {
        return (projectData[tokenId]);
    }

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
        return
            interfaceId == type(IAccessControlUpgradeable).interfaceId ||
            ERC721Upgradeable.supportsInterface(interfaceId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string calldata gateway) external virtual {
        _onlyOwner();
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
        _tokenExists(tokenId);

        string memory uri = projectData[tokenId].uri;
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

    function memcmp(bytes memory a, bytes memory b)
        internal
        pure
        returns (bool)
    {
        return (a.length == b.length) && (keccak256(a) == keccak256(b));
    }

    function strcmp(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return memcmp(bytes(a), bytes(b));
    }

    error CallerNotAllowed();
    error OnlyOwner();
    error NotManagerOrOwner();
    error TokenDoesNotExist();
    error ProjectIdAlreadyExists();
    error ProjectIdCannotBeEmpty();
    error ContractPaused();
}
