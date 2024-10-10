// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol';

import '../interfaces/IToucanContractRegistry.sol';
import '../libraries/Strings.sol';
import '../token/ERC1155Allowable.sol';
import '../bases/RoleInitializer.sol';
import './interfaces/IRetirementCertificates.sol';
import './interfaces/IRetirementCertificateFractionalizer.sol';
import './interfaces/IRetirementCertificateFractions.sol';
import './RetirementCertificateFractionalizerStorage.sol';

/// @notice The `RetirementCertificateFractionalizer` contract lets users mint fractions of retirement certificates.
/// Users must first deposit a retirement certificate into this contract to mint fractions.
contract RetirementCertificateFractionalizer is
    IRetirementCertificateFractionalizer,
    ERC1155Allowable,
    ERC1155SupplyUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    RoleInitializer,
    RetirementCertificateFractionalizerStorage
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
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @dev All roles related to accessing this contract
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event ToucanRegistrySet(address contractRegistry);
    event BeneficiaryStringSet(string beneficiaryString);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(
        address _contractRegistry,
        string memory _beneficiaryString,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external virtual initializer {
        __Context_init_unchained();
        __ERC1155_init_unchained('');
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();

        __RoleInitializer_init_unchained(accounts, roles);

        contractRegistry = _contractRegistry;
        beneficiaryString = _beneficiaryString;
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
        override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ------------------------
    //      Admin functions
    // ------------------------

    function setToucanContractRegistry(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        contractRegistry = _address;
        emit ToucanRegistrySet(_address);
    }

    /// @notice Set the beneficiary string that every certificate sent to this contract must have
    /// @param _beneficiaryString The only accepted beneficiary string for certificates sent to this contract
    /// @dev Callable only by admins
    function setBeneficiaryString(string memory _beneficiaryString)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        beneficiaryString = _beneficiaryString;
        emit BeneficiaryStringSet(_beneficiaryString);
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

    // ----------------------------------
    //     Permissionless functions
    // ----------------------------------

    /// @notice Mint a fraction of a retirement certificate, from the balance of the caller
    /// @param params The request data of the fraction to mint
    /// @return fractionTokenId The id of the minted fraction NFT, in the fractions contract
    function mintFraction(FractionRequestData calldata params)
        external
        whenNotPaused
        returns (uint256 fractionTokenId)
    {
        return _mintFractionFrom(_msgSender(), params);
    }

    /// @notice Mint a fraction of a retirement certificate, from the balance of the listing owner
    /// @param from The owner of the balance to mint the fraction from
    /// @param params The request data of the fraction to mint
    /// @return fractionTokenId The id of the minted fraction NFT, in the fractions contract
    function mintFractionFrom(address from, FractionRequestData calldata params)
        public
        whenNotPaused
        returns (uint256 fractionTokenId)
    {
        require(params.amount > 0, 'Amount must be greater than 0');
        if (from != _msgSender() && !isApprovedForAll(from, _msgSender())) {
            _decreaseAllowance(
                from,
                _msgSender(),
                params.projectVintageTokenId,
                params.amount
            );
        }
        fractionTokenId = _mintFractionFrom(from, params);
    }

    function _mintFractionFrom(
        address from,
        FractionRequestData calldata params
    ) internal returns (uint256 fractionTokenId) {
        // reduce the fraction's amount from the owner's balance
        // this also checks if the owner has enough balance
        _burn(from, params.projectVintageTokenId, params.amount);

        FractionData memory fractionData = FractionData({
            amount: params.amount,
            projectVintageTokenId: params.projectVintageTokenId,
            createdAt: block.timestamp,
            fractioningEntity: from,
            beneficiary: params.beneficiary,
            beneficiaryString: params.beneficiaryString,
            retirementMessage: params.retirementMessage,
            beneficiaryLocation: params.beneficiaryLocation,
            consumptionCountryCode: params.consumptionCountryCode,
            consumptionPeriodStart: params.consumptionPeriodStart,
            consumptionPeriodEnd: params.consumptionPeriodEnd,
            tokenURI: params.tokenURI,
            extraData: params.extraData
        });
        address rcFractions = IToucanContractRegistry(contractRegistry)
            .retirementCertificateFractionsAddress();
        fractionTokenId = IRetirementCertificateFractions(rcFractions)
            .mintFraction(_msgSender(), fractionData);
    }

    /// @dev by depositing a retirement certificate into this contract, the sender gets
    /// the right to mint fractions based on the amount of the certificate
    function onERC721Received(
        address, /* operator */
        address from,
        uint256 tokenId,
        bytes calldata /* data */
    ) external virtual returns (bytes4) {
        address retirementCertificatesAddress = IToucanContractRegistry(
            contractRegistry
        ).retirementCertificatesAddress();
        require(
            msg.sender == retirementCertificatesAddress,
            'Only RetirementCertificates can be sent to this contract'
        );
        IRetirementCertificates retirementCertificates = IRetirementCertificates(
                retirementCertificatesAddress
            );
        CertificateData memory certificateData = retirementCertificates.getData(
            tokenId
        );
        require(
            certificateData.beneficiary == address(this),
            'Beneficiary of the certificate must be this contract'
        );
        require(
            certificateData.beneficiaryString.equals(beneficiaryString),
            string.concat('Beneficiary string must be ', beneficiaryString)
        );

        // Add the certificate amounts to the balance of the sender
        uint256[] memory retirementEventIds = certificateData
            .retirementEventIds;
        for (uint256 i = 0; i < retirementEventIds.length; i++) {
            RetirementEvent memory retirement = retirementCertificates
                .retirements(retirementEventIds[i]);
            _mint(
                from,
                retirement.projectVintageTokenId,
                retirement.amount,
                ''
            );
            // Add the retirement event ids to the FIFO queue of the sender
            // and keep track of its remaining balance
            _retirementEventIds[from][retirement.projectVintageTokenId].push(
                retirementEventIds[i]
            );
            remainingRetirementEventBalance[retirementEventIds[i]] += retirement
                .amount;
        }

        return this.onERC721Received.selector;
    }

    /// @notice Get the FIFO queue of retirement event ids for a given owner and vintage
    /// @param owner The owner of the retirement event ids; this is the original depositor
    /// of the parent retirement certificate in the fractionalizer.
    /// @param vintageId The project vintage of the retirement events
    /// @return An array of retirement event ids
    function getRetirementEventIds(address owner, uint256 vintageId)
        external
        view
        returns (uint256[] memory)
    {
        return _retirementEventIds[owner][vintageId];
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        if (to == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                totalBurntSupply[ids[i]] += amounts[i];
            }
        }
        if (from != address(0) && to != address(0)) {
            revert('Transfers are not allowed yet');
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override(ERC1155Upgradeable, ERC1155Allowable) {
        ERC1155Allowable.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override(ERC1155Upgradeable, ERC1155Allowable) {
        ERC1155Allowable.safeTransferFrom(from, to, id, amount, data);
    }
}
