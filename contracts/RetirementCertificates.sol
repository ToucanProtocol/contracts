// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './interfaces/IToucanContractRegistry.sol';
import './RetirementCertificatesStorage.sol';

/// @notice The `RetirementCertificates` contract lets users mint NFTs that act as proof-of-retirement.
/// These Retirement Certificate NFTs display how many kilos of CO2-equivalent a user has burnt
contract RetirementCertificates is
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    RetirementCertificatesStorage
{
    // ----------------------------------------
    //      Libraries
    // ----------------------------------------

    using AddressUpgradeable for address;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

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

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    /// @dev Returns the current version of the smart contract
    function version() public pure virtual returns (string memory) {
        return '1.0.0';
    }

    function initialize(address _contractRegistry, string memory _baseURI)
        public
        virtual
        initializer
    {
        __Context_init_unchained();
        __ERC721_init_unchained(
            'Toucan Protocol: Retirement Certificates for Tokenized Carbon Offsets',
            'TOUCAN-CERT'
        );
        __Ownable_init_unchained();
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
        public
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
            IToucanContractRegistry(contractRegistry).checkERC20(
                _msgSender()
            ) == true,
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
    /// @param retirementEventIds An array of event ids to associate with the NFT. Currently
    /// only 1 event is allowed to be provided here.
    function _attachRetirementEvents(
        uint256 tokenId,
        address retiringEntity,
        uint256[] calldata retirementEventIds
    ) internal {
        // 0. Check whether retirementEventIds is empty
        // 1. Check whether event belongs to user (retiring entity)
        // 2. Check whether the event has previously been attached
        require(retirementEventIds.length != 0, 'Empty event array');
        for (uint256 i; i < retirementEventIds.length; ++i) {
            require(
                retirements[retirementEventIds[i]].retiringEntity ==
                    retiringEntity,
                'Invalid event to be claimed'
            );
            require(
                !claimedEvents[retirementEventIds[i]],
                'Already claimed event'
            );
            claimedEvents[retirementEventIds[i]] = true;
            certificates[tokenId].retirementEventIds.push(
                retirementEventIds[i]
            );
        }
    }

    /// @notice Mint new Retirement Certificate NFT that shows how many TCO2s have been retired.
    /// @param retiringEntity The entity that has retired TCO2 and is eligible to mint an NFT.
    /// @param retiringEntityString An identifiable string for the retiring entity, eg. their name.
    /// @param beneficiary The beneficiary address for whom the TCO2 amount was retired.
    /// @param beneficiaryString An identifiable string for the beneficiary, eg. their name.
    /// @param retirementMessage A message to accompany the retirement.
    /// @param retirementEventIds An array of event ids to associate with the NFT. Currently
    /// only 1 event is allowed to be provided here.
    /// @dev    The function can either be called by a valid TCO2 contract or by someone who
    ///         owns retirement events.
    function mintCertificate(
        address retiringEntity,
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256[] calldata retirementEventIds
    ) external virtual {
        // If the provided retiring entity is not the caller, then
        // ensure the caller is at least a TCO2 contract. This is to
        // allow TCO2 contracts to call retireAndMintCertificate.
        require(
            retiringEntity == msg.sender ||
                IToucanContractRegistry(contractRegistry).checkERC20(
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

        _safeMint(retiringEntity, newItemId);

        // Attach retirement events to the newly minted NFT
        _attachRetirementEvents(newItemId, retiringEntity, retirementEventIds);

        certificates[newItemId].createdAt = block.timestamp;
        certificates[newItemId].beneficiary = beneficiary;
        certificates[newItemId].beneficiaryString = beneficiaryString;
        certificates[newItemId].retiringEntity = retiringEntity;
        certificates[newItemId].retiringEntityString = retiringEntityString;
        certificates[newItemId].retirementMessage = retirementMessage;

        emit CertificateMinted(newItemId);
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
        return
            string(
                abi.encodePacked(baseURI, StringsUpgradeable.toString(tokenId))
            );
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

    /// @notice Get certificate data for an NFT.
    /// @param tokenId The id of the NFT to get data for.
    function getData(uint256 tokenId) public view returns (Data memory) {
        return certificates[tokenId];
    }

    /// @notice Get all events for a user.
    /// @param user The user for whom to fetch all events.
    function getUserEvents(address user)
        public
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
        uint256 amount;
        uint256[] memory eventIds = certificates[tokenId].retirementEventIds;
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
        uint256 amount;
        uint256[] memory eventIds = certificates[tokenId].retirementEventIds;
        for (uint256 i; i < eventIds.length; ++i) {
            amount += retirements[eventIds[i]].amount;
        }
        return amount / kiloDenomination;
    }
}
