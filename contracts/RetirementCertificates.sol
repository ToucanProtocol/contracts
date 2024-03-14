// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './bases/ToucanCarbonOffsetsWithBatchBaseTypes.sol';
import './interfaces/ICarbonProjectVintages.sol';
import './interfaces/IToucanCarbonOffsets.sol';
import './interfaces/IToucanContractRegistry.sol';
import './libraries/Strings.sol';
import './RetirementCertificatesStorage.sol';

/// @notice The `RetirementCertificates` contract lets users mint NFTs that act as proof-of-retirement.
/// These Retirement Certificate NFTs display how many TCO2s a user has burnt
/// @dev The amount of RetirementEvents is denominated in the 18-decimal form
/// @dev Getters in this contract return the corresponding amount in tonnes or kilos
contract RetirementCertificates is
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    RetirementCertificatesStorageV1,
    ReentrancyGuardUpgradeable,
    RetirementCertificatesStorage
{
    // ----------------------------------------
    //      Libraries
    // ----------------------------------------

    using Strings for string;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.1.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @dev dividers to round carbon in human-readable denominations
    uint256 public constant tonneDenomination = 1e18;
    uint256 public constant kiloDenomination = 1e15;

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event CertificateMinted(uint256 tokenId);
    event CertificateUpdated(uint256 tokenId);
    event ToucanRegistrySet(address ContractRegistry);
    event BaseURISet(string baseURI);
    event MinValidAmountSet(uint256 previousAmount, uint256 newAmount);
    event EventsAttached(uint256 tokenId, uint256[] eventIds);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address _contractRegistry, string memory _baseURI)
        external
        virtual
        initializer
    {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'Toucan Protocol: Retirement Certificates for Tokenized Carbon Offsets',
            'TOUCAN-CERT'
        );
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();

        contractRegistry = _contractRegistry;
        baseURI = _baseURI;
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

    function setToucanContractRegistry(address _address)
        external
        virtual
        onlyOwner
    {
        contractRegistry = _address;
        emit ToucanRegistrySet(_address);
    }

    function setBaseURI(string memory baseURI_) external virtual onlyOwner {
        baseURI = baseURI_;
        emit BaseURISet(baseURI_);
    }

    function setMinValidRetirementAmount(uint256 amount) external onlyOwner {
        uint256 previousAmount = minValidRetirementAmount;
        require(previousAmount != amount, 'Already set');

        minValidRetirementAmount = amount;
        emit MinValidAmountSet(previousAmount, amount);
    }

    // ----------------------------------
    //     Permissionless functions
    // ----------------------------------

    /// @notice Register retirement events. This function can only be called by a TC02 contract
    /// to register retirement events so they can be directly linked to an NFT mint.
    /// @param retiringEntity The entity that has retired TCO2 and is eligible to mint an NFT.
    /// @param projectVintageTokenId The vintage id of the TCO2 that is retired.
    /// @param amount The amount of the TCO2 that is retired.
    /// @param isLegacy Whether this event registration was executed by using the legacy retired
    /// amount in the TCO2 contract or utilizes the new retirement event design.
    /// @dev    The function can either be only called by a valid TCO2 contract.
    function registerEvent(
        address retiringEntity,
        uint256 projectVintageTokenId,
        uint256 amount,
        bool isLegacy
    ) external returns (uint256) {
        // Logic requires that minting can only originate from a project-vintage ERC20 contract
        require(
            IToucanContractRegistry(contractRegistry).isValidERC20(msg.sender),
            'Caller not a TCO2'
        );
        require(
            amount != 0 && amount >= minValidRetirementAmount,
            'Invalid amount'
        );

        /// Read from storage once, then use everywhere by reading
        /// from memory.
        uint256 eventCounter = retireEventCounter;
        unchecked {
            /// Realistically, the counter will never overflow
            ++eventCounter;
        }
        /// Store counter back in storage
        retireEventCounter = eventCounter;

        // Track all events of a user
        eventsOfUser[retiringEntity].push(eventCounter);
        // Track retirements
        if (!isLegacy) {
            // Avoid tracking timestamps for legacy retirements since these
            // are inaccurate.
            retirements[eventCounter].createdAt = block.timestamp;
        }
        retirements[eventCounter].retiringEntity = retiringEntity;
        retirements[eventCounter].amount = amount;
        retirements[eventCounter].projectVintageTokenId = projectVintageTokenId;

        return eventCounter;
    }

    /// @notice Attach retirement events to an NFT.
    /// @param tokenId The id of the NFT to attach events to.
    /// @param retirementEventIds An array of event ids to associate with the NFT.
    function attachRetirementEvents(
        uint256 tokenId,
        uint256[] calldata retirementEventIds
    ) external {
        address tokenOwner = ownerOf(tokenId);
        require(tokenOwner == msg.sender, 'Unauthorized');
        _attachRetirementEvents(tokenId, tokenOwner, retirementEventIds);
    }

    /// @notice Attach retirement events to an NFT.
    /// @param tokenId The id of the NFT to attach events to.
    /// @param retiringEntity The entity that has retired TCO2 and is eligible to mint an NFT.
    /// @param retirementEventIds An array of event ids to associate with the NFT.
    function _attachRetirementEvents(
        uint256 tokenId,
        address retiringEntity,
        uint256[] calldata retirementEventIds
    ) internal {
        // 0. Check whether retirementEventIds is empty
        // 1. Check whether event belongs to user (retiring entity)
        // 2. Check whether the event has previously been attached
        require(retirementEventIds.length != 0, 'Empty event array');
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < retirementEventIds.length; ++i) {
            uint256 eventId = retirementEventIds[i];
            require(
                retirements[eventId].retiringEntity == retiringEntity,
                'Invalid event to be claimed'
            );
            require(!claimedEvents[eventId], 'Already claimed event');
            claimedEvents[eventId] = true;
            certificates[tokenId].retirementEventIds.push(eventId);
        }
        emit EventsAttached(tokenId, retirementEventIds);
    }

    /// @notice Mint new Retirement Certificate NFT that shows how many TCO2s have been retired.
    /// @param retiringEntity The entity that has retired TCO2 and is eligible to mint an NFT.
    /// @param retiringEntityString An identifiable string for the retiring entity, eg. their name.
    /// @param beneficiary The beneficiary address for whom the TCO2 amount was retired.
    /// @param beneficiaryString An identifiable string for the beneficiary, eg. their name.
    /// @param retirementMessage A message to accompany the retirement.
    /// @param retirementEventIds An array of event ids to associate with the NFT.
    /// @return The token id of the newly minted NFT.
    /// @dev    The function can either be called by a valid TCO2 contract or by someone who
    ///         owns retirement events.
    function mintCertificate(
        address retiringEntity,
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256[] calldata retirementEventIds
    ) external virtual nonReentrant returns (uint256) {
        CreateRetirementRequestParams
            memory params = CreateRetirementRequestParams({
                tokenIds: new uint256[](0),
                amount: 0,
                retiringEntityString: retiringEntityString,
                beneficiary: beneficiary,
                beneficiaryString: beneficiaryString,
                retirementMessage: retirementMessage,
                beneficiaryLocation: '',
                consumptionCountryCode: '',
                consumptionPeriodStart: 0,
                consumptionPeriodEnd: 0
            });
        return _mintCertificate(retiringEntity, params, retirementEventIds);
    }

    function _mintCertificate(
        address retiringEntity,
        CreateRetirementRequestParams memory params,
        uint256[] calldata retirementEventIds
    ) internal returns (uint256) {
        // If the provided retiring entity is not the caller, then
        // ensure the caller is at least a TCO2 contract. This is to
        // allow TCO2 contracts to call retireAndMintCertificate.
        require(
            retiringEntity == msg.sender ||
                IToucanContractRegistry(contractRegistry).isValidERC20(
                    msg.sender
                ) ==
                true,
            'Invalid caller'
        );

        uint256 newItemId = _tokenIds;
        unchecked {
            ++newItemId;
        }
        _tokenIds = newItemId;

        // Attach retirement events to the newly minted NFT
        _attachRetirementEvents(newItemId, retiringEntity, retirementEventIds);

        certificates[newItemId].createdAt = block.timestamp;
        certificates[newItemId].beneficiary = params.beneficiary;
        certificates[newItemId].beneficiaryString = params.beneficiaryString;
        certificates[newItemId].retiringEntity = retiringEntity;
        certificates[newItemId].retiringEntityString = params
            .retiringEntityString;
        certificates[newItemId].retirementMessage = params.retirementMessage;
        certificates[newItemId].beneficiaryLocation = params
            .beneficiaryLocation;
        certificates[newItemId].consumptionCountryCode = params
            .consumptionCountryCode;
        certificates[newItemId].consumptionPeriodStart = params
            .consumptionPeriodStart;
        certificates[newItemId].consumptionPeriodEnd = params
            .consumptionPeriodEnd;

        emit CertificateMinted(newItemId);
        _safeMint(retiringEntity, newItemId);

        return newItemId;
    }

    /// @notice Mint new Retirement Certificate NFT that shows how many TCO2s have been retired.
    /// @param retiringEntity The entity that has retired TCO2 and is eligible to mint an NFT.
    /// @param params Retirement params
    /// @param retirementEventIds An array of event ids to associate with the NFT.
    /// @return The token id of the newly minted NFT.
    /// @dev    The function can either be called by a valid TCO2 contract or by someone who
    ///         owns retirement events.
    function mintCertificateWithExtraData(
        address retiringEntity,
        CreateRetirementRequestParams calldata params,
        uint256[] calldata retirementEventIds
    ) external virtual nonReentrant returns (uint256) {
        return _mintCertificate(retiringEntity, params, retirementEventIds);
    }

    /// @param tokenId The id of the NFT to get the URI.
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
        return string.concat(baseURI, StringsUpgradeable.toString(tokenId));
    }

    /// @notice Update retirementMessage, beneficiary, and beneficiaryString of a NFT
    /// within 24h of creation. Empty values are ignored, ie., will not overwrite the
    /// existing stored values in the NFT.
    /// @param tokenId The id of the NFT to update.
    /// @param retiringEntityString An identifiable string for the retiring entity, eg. their name.
    /// @param beneficiary The new beneficiary to set in the NFT.
    /// @param beneficiaryString An identifiable string for the beneficiary, eg. their name.
    /// @param retirementMessage The new retirementMessage to set in the NFT.
    function updateCertificate(
        uint256 tokenId,
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage
    ) external virtual {
        string[] memory registries = new string[](1);
        registries[0] = 'verra';
        require(
            isCertificateForRegistry(tokenId, registries),
            'Invalid registry'
        );
        require(msg.sender == ownerOf(tokenId), 'Sender is not owner');
        require(
            block.timestamp < certificates[tokenId].createdAt + 24 hours,
            '24 hours elapsed'
        );

        if (bytes(retiringEntityString).length != 0) {
            certificates[tokenId].retiringEntityString = retiringEntityString;
        }
        if (beneficiary != address(0)) {
            certificates[tokenId].beneficiary = beneficiary;
        }
        if (bytes(beneficiaryString).length != 0) {
            certificates[tokenId].beneficiaryString = beneficiaryString;
        }
        if (bytes(retirementMessage).length != 0) {
            certificates[tokenId].retirementMessage = retirementMessage;
        }

        emit CertificateUpdated(tokenId);
    }

    function isCertificateForRegistry(
        uint256 tokenId,
        string[] memory registries
    ) public view returns (bool) {
        // Determine the registry of the certificate
        uint256 eventId = certificates[tokenId].retirementEventIds[0];
        uint256 projectVintageTokenId = retirements[eventId]
            .projectVintageTokenId;
        VintageData memory data = ICarbonProjectVintages(
            IToucanContractRegistry(contractRegistry)
                .carbonProjectVintagesAddress()
        ).getProjectVintageDataByTokenId(projectVintageTokenId);
        string memory registry = data.registry;
        if (bytes(registry).length == 0) {
            // For backwards-compatibility
            registry = 'verra';
        }

        // Loop through the registries and check if the certificate is for one of them
        for (uint256 i = 0; i < registries.length; i++) {
            if (registry.equals(registries[i])) {
                return true;
            }
        }

        return false;
    }

    /// @notice Get certificate data for an NFT.
    /// @param tokenId The id of the NFT to get data for.
    function getData(uint256 tokenId) external view returns (Data memory) {
        return certificates[tokenId];
    }

    /// @notice Get all events for a user.
    /// @param user The user for whom to fetch all events.
    function getUserEvents(address user)
        external
        view
        returns (uint256[] memory)
    {
        return eventsOfUser[user];
    }

    /// @notice Get total retired amount for an NFT.
    /// @param tokenId The id of the NFT to update.
    /// @return amount Total retired amount for an NFT.
    /// @dev The return amount is denominated in 18 decimals, similar to amounts
    /// as they are read in TCO2 contracts.
    /// For example, 1000000000000000000 means 1 tonne.
    function getRetiredAmount(uint256 tokenId)
        external
        view
        returns (uint256 amount)
    {
        uint256[] memory eventIds = certificates[tokenId].retirementEventIds;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < eventIds.length; ++i) {
            amount += retirements[eventIds[i]].amount;
        }
    }

    /// @notice Get total retired amount for an NFT in tonnes.
    /// @param tokenId The id of the NFT to update.
    /// @return amount Total retired amount for an NFT in tonnes.
    function getRetiredAmountInTonnes(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        //slither-disable-next-line uninitialized-local
        uint256 amount;
        uint256[] memory eventIds = certificates[tokenId].retirementEventIds;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < eventIds.length; ++i) {
            amount += retirements[eventIds[i]].amount;
        }
        return amount / tonneDenomination;
    }

    /// @notice Get total retired amount for an NFT in kilos.
    /// @param tokenId The id of the NFT to update.
    /// @return amount Total retired amount for an NFT in kilos.
    function getRetiredAmountInKilos(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        //slither-disable-next-line uninitialized-local
        uint256 amount;
        uint256[] memory eventIds = certificates[tokenId].retirementEventIds;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < eventIds.length; ++i) {
            amount += retirements[eventIds[i]].amount;
        }
        return amount / kiloDenomination;
    }
}
