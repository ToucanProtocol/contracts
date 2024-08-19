// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import '../bases/RoleInitializer.sol';
import '../interfaces/IToucanCarbonOffsets.sol';
import '../interfaces/IToucanContractRegistry.sol';
import {Errors} from '../libraries/Errors.sol';
import '../libraries/Strings.sol';
import './PoolFilterStorage.sol';

abstract contract PoolFilter is
    ContextUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    RoleInitializer,
    UUPSUpgradeable,
    PoolFilterStorage
{
    using Strings for string;

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event AttributeMethodologyAdded(string methodology);
    event AttributeMethodologyRemoved(string methodology);
    event AttributeRegionAdded(string region);
    event AttributeRegionRemoved(string region);
    event AttributeStandardAdded(string standard);
    event AttributeStandardRemoved(string standard);
    event ExternalAddressRemovedFromAllowlist(address erc20addr);
    event ExternalAddressAllowlisted(address erc20addr);
    event ExternalERC1155TokenAllowlisted(
        address tokenAddress,
        uint256 tokenId
    );
    event ExternalERC1155TokenRemovedFromAllowlist(
        address tokenAddress,
        uint256 tokenId
    );
    event InternalAddressBlocklisted(address erc20addr);
    event InternalAddressRemovedFromBlocklist(address erc20addr);
    event InternalAddressRemovedFromAllowlist(address erc20addr);
    event InternalAddressAllowlisted(address erc20addr);
    event MappingSwitched(string mappingName, bool accepted);
    event MinimumVintageStartTimeUpdated(uint256 minimumVintageStartTime);
    event ToucanRegistrySet(address registry);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __PoolFilter_init_unchained(
        address[] calldata accounts,
        bytes32[] calldata roles
    ) internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __RoleInitializer_init_unchained(accounts, roles);
        __UUPSUpgradeable_init_unchained();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function _authorizeUpgrade(address) internal virtual override {
        onlyPoolOwner();
    }

    // ------------------------
    // Poor person's modifiers
    // ------------------------

    /// @dev function that checks whether the caller is the
    /// contract owner
    function onlyPoolOwner() internal view {
        require(owner() == msg.sender, Errors.CP_ONLY_OWNER);
    }

    // ----------------------------------------
    //      Read-only functions
    // ----------------------------------------

    /// @notice Checks if an ERC20 token is eligible for this pool
    /// @param erc20Addr The ERC20 token
    /// @return String with error code if any error occurs, else empty string
    function checkEligible(address erc20Addr)
        external
        view
        virtual
        returns (string memory)
    {
        bool isToucanContract = IToucanContractRegistry(contractRegistry)
            .isValidERC20(erc20Addr);

        if (isToucanContract) {
            if (internalAllowlist[erc20Addr]) {
                return '';
            }

            if (internalBlocklist[erc20Addr]) {
                return Errors.CP_BLOCKLISTED;
            }

            return checkAttributeMatching(erc20Addr);
        } else {
            /// @dev If not Toucan native contract, check if address is allowlisted
            if (!externalAllowlist[erc20Addr]) {
                return Errors.CP_NOT_ALLOWLISTED;
            }
        }

        return '';
    }

    /// @notice Checks if an ERC-1155 token is eligible for this pool
    /// @param tokenAddress address of the ERC1155 token
    /// @param tokenId ID of the ERC1155 token
    /// @return String with error code if any error occurs, else empty string
    function checkERC1155Eligible(address tokenAddress, uint256 tokenId)
        external
        view
        returns (string memory)
    {
        if (!externalERC1155Allowlist[tokenAddress][tokenId])
            return Errors.CP_NOT_ALLOWLISTED;

        return '';
    }

    /// @notice Checks whether incoming ERC20s match the accepted criteria/attributes
    /// @param erc20Addr The ERC20 token
    /// @return String with error code if any error occurs, else empty string
    function checkAttributeMatching(address erc20Addr)
        public
        view
        virtual
        returns (string memory)
    {
        ProjectData memory projectData;
        VintageData memory vintageData;
        (projectData, vintageData) = IToucanCarbonOffsets(erc20Addr)
            .getAttributes();

        /// @dev checks if any one of the attributes are blocklisted.
        /// If mappings are set to "allowlist"-mode, require the opposite
        if (vintageData.startTime < minimumVintageStartTime)
            return Errors.CP_START_TIME_TOO_OLD;

        if (regions[projectData.region] != regionsIsAcceptedMapping)
            return Errors.CP_REGION_NOT_ACCEPTED;

        if (standards[projectData.standard] != standardsIsAcceptedMapping)
            return Errors.CP_STANDARD_NOT_ACCEPTED;

        if (
            methodologies[projectData.methodology] !=
            methodologiesIsAcceptedMapping
        ) return Errors.CP_METHODOLOGY_NOT_ACCEPTED;

        return '';
    }

    // ----------------------------------------
    //      Admin functions
    // ----------------------------------------

    function setToucanContractRegistry(address _address) external {
        onlyPoolOwner();
        contractRegistry = _address;
        emit ToucanRegistrySet(_address);
    }

    /// @notice Generic function to switch attributes mappings into either
    /// acceptance or rejection criteria
    /// @param _mappingName attribute mapping of project-vintage data
    /// @param accepted determines if mapping works as a blocklist or allowlist
    function switchMapping(string memory _mappingName, bool accepted) external {
        onlyPoolOwner();
        if (_mappingName.equals('regions')) {
            accepted
                ? regionsIsAcceptedMapping = true
                : regionsIsAcceptedMapping = false;
        } else if (_mappingName.equals('standards')) {
            accepted
                ? standardsIsAcceptedMapping = true
                : standardsIsAcceptedMapping = false;
        } else if (_mappingName.equals('methodologies')) {
            accepted
                ? methodologiesIsAcceptedMapping = true
                : methodologiesIsAcceptedMapping = false;
        }
        emit MappingSwitched(_mappingName, accepted);
    }

    /// @notice Function to add attributes for filtering (does not support complex AttributeSets)
    /// @param addToList determines whether attribute should be added or removed
    /// Other params are arrays of attributes to be added
    function addAttributes(
        bool addToList,
        string[] memory _regions,
        string[] memory _standards,
        string[] memory _methodologies
    ) external virtual {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < _standards.length; ++i) {
            if (addToList == true) {
                standards[_standards[i]] = true;
                emit AttributeStandardAdded(_standards[i]);
            } else {
                standards[_standards[i]] = false;
                emit AttributeStandardRemoved(_standards[i]);
            }
        }

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < _methodologies.length; ++i) {
            if (addToList == true) {
                methodologies[_methodologies[i]] = true;
                emit AttributeMethodologyAdded(_methodologies[i]);
            } else {
                methodologies[_methodologies[i]] = false;
                emit AttributeMethodologyRemoved(_methodologies[i]);
            }
        }

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < _regions.length; ++i) {
            if (addToList == true) {
                regions[_regions[i]] = true;
                emit AttributeRegionAdded(_regions[i]);
            } else {
                regions[_regions[i]] = false;
                emit AttributeRegionRemoved(_regions[i]);
            }
        }
    }

    /// @notice Function to allowlist selected external non-TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToExternalAllowlist(address[] memory erc20Addr) external {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            externalAllowlist[erc20Addr[i]] = true;
            emit ExternalAddressAllowlisted(erc20Addr[i]);
        }
    }

    /// @notice Add ERC-1155 tokens to external allowlist
    /// @param tokenAddresses An array of contract addresses
    /// @param tokenIds An array of token IDs
    /// @dev Both arrays must be of the same length. Each token address is associated
    /// with the token ID at the same index.
    function addToExternalERC1155Allowlist(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds
    ) external {
        onlyPoolOwner();
        uint256 tokensLen = tokenAddresses.length;
        if (tokensLen != tokenIds.length) revert(Errors.CP_LENGTH_MISMATCH);

        for (uint256 i = 0; i < tokensLen; ++i) {
            externalERC1155Allowlist[tokenAddresses[i]][tokenIds[i]] = true;
            emit ExternalERC1155TokenAllowlisted(
                tokenAddresses[i],
                tokenIds[i]
            );
        }
    }

    /// @notice Function to allowlist certain TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToInternalAllowlist(address[] memory erc20Addr) external {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalAllowlist[erc20Addr[i]] = true;
            emit InternalAddressAllowlisted(erc20Addr[i]);
        }
    }

    /// @notice Function to blocklist certain TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToInternalBlocklist(address[] memory erc20Addr) external {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalBlocklist[erc20Addr[i]] = true;
            emit InternalAddressBlocklisted(erc20Addr[i]);
        }
    }

    /// @notice Function to remove ERC20 addresses from external allowlist
    /// @param erc20Addr accepts an array of contract addresses
    function removeFromExternalAllowlist(address[] memory erc20Addr) external {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            externalAllowlist[erc20Addr[i]] = false;
            emit ExternalAddressRemovedFromAllowlist(erc20Addr[i]);
        }
    }

    /// @notice Remove ERC-1155 tokens from external allowlist
    /// @param tokenAddresses An array of contract addresses
    /// @param tokenIds An array of token IDs
    /// @dev Both arrays must be of the same length. Each token address is associated
    /// with the token ID at the same index.
    function removeFromExternalERC1155Allowlist(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds
    ) external {
        onlyPoolOwner();
        uint256 tokensLen = tokenAddresses.length;
        if (tokensLen != tokenIds.length) revert(Errors.CP_LENGTH_MISMATCH);

        for (uint256 i = 0; i < tokensLen; ++i) {
            externalERC1155Allowlist[tokenAddresses[i]][tokenIds[i]] = false;
            emit ExternalERC1155TokenRemovedFromAllowlist(
                tokenAddresses[i],
                tokenIds[i]
            );
        }
    }

    /// @notice Function to remove TCO2 addresses from internal blocklist
    /// @param erc20Addr accepts an array of contract addresses
    function removeFromInternalBlocklist(address[] memory erc20Addr) external {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalBlocklist[erc20Addr[i]] = false;
            emit InternalAddressRemovedFromBlocklist(erc20Addr[i]);
        }
    }

    /// @notice Function to remove TCO2 addresses from internal allowlist
    /// @param erc20Addr accepts an array of contract addressesc
    function removeFromInternalAllowlist(address[] memory erc20Addr) external {
        onlyPoolOwner();
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalAllowlist[erc20Addr[i]] = false;
            emit InternalAddressRemovedFromAllowlist(erc20Addr[i]);
        }
    }

    /// @notice Determines the minimum vintage start time acceptance criteria of ERC20s
    /// @param _minimumVintageStartTime unix time format
    function setMinimumVintageStartTime(uint64 _minimumVintageStartTime)
        external
    {
        onlyPoolOwner();
        minimumVintageStartTime = _minimumVintageStartTime;
        emit MinimumVintageStartTimeUpdated(_minimumVintageStartTime);
    }
}
