// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

import '../interfaces/ICarbonOffsetBatches.sol';
import '../interfaces/ICarbonProjects.sol';
import '../interfaces/ICarbonProjectVintages.sol';
import '../interfaces/IPausable.sol';
import '../interfaces/IRetirementCertificates.sol';
import '../interfaces/IToucanCarbonOffsetsEscrow.sol';
import '../interfaces/IToucanCarbonOffsetsFactory.sol';
import '../interfaces/IToucanContractRegistry.sol';
import '../CarbonProjectTypes.sol';
import '../CarbonProjectVintageTypes.sol';
import '../ToucanCarbonOffsetsStorage.sol';
import '../CarbonOffsetBatchesTypes.sol';

/// @notice Base contract for any specific contract implementation of the TCO2 tokens (ERC20)
abstract contract ToucanCarbonOffsetsBase is
    ERC20Upgradeable,
    ToucanCarbonOffsetsStorage
{
    // ----------------------------------------
    //              Constants
    // ----------------------------------------

    /// @dev All roles related to accessing this contract
    bytes32 public constant DETOKENIZER_ROLE = keccak256('DETOKENIZER_ROLE');
    bytes32 public constant TOKENIZER_ROLE = keccak256('TOKENIZER_ROLE');
    bytes32 public constant RETIREMENT_ROLE = keccak256('RETIREMENT_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event FeePaid(address bridger, uint256 fees);
    event FeeBurnt(address bridger, uint256 fees);
    event Retired(address sender, uint256 amount, uint256 eventId);

    // ----------------------------------------
    //              Modifiers
    // ----------------------------------------

    /// @dev modifier checks whether the `ToucanCarbonOffsetsFactory` is paused
    /// Since TCO2 contracts are permissionless, pausing does not function individually
    modifier whenNotPaused() {
        address tco2Factory = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsFactoryAddress(standardRegistry());
        bool _paused = IPausable(tco2Factory).paused();
        require(!_paused, 'Paused TCO2');
        _;
    }

    modifier onlyBridges() {
        address tco2Factory = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsFactoryAddress(standardRegistry());
        bool isAllowed = IToucanCarbonOffsetsFactory(tco2Factory)
            .allowedBridges(msg.sender);
        require(isAllowed, 'Not allowed');
        _;
    }

    modifier onlyFactoryOwner() {
        address tco2Factory = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsFactoryAddress(standardRegistry());
        address owner = IToucanCarbonOffsetsFactory(tco2Factory).owner();
        require(owner == msg.sender, 'Not factory owner');
        _;
    }

    // Modifer that checks if the msg.sender has the required role
    modifier onlyWithRole(bytes32 role) {
        require(
            IToucanCarbonOffsetsFactory(
                IToucanContractRegistry(contractRegistry)
                    .toucanCarbonOffsetsFactoryAddress(standardRegistry())
            ).hasRole(role, msg.sender),
            'Invalid access'
        );
        _;
    }

    // Modifier that checks if msg.sender is the escrow contract
    modifier onlyEscrow() {
        require(
            IToucanContractRegistry(contractRegistry)
                .toucanCarbonOffsetsEscrowAddress() == msg.sender,
            'Not escrow contract'
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Bridge-related functions
    // ----------------------------------------

    /// @notice Burn TCO2 on behalf of a user. msg.sender does not require approval
    /// by the account for the burn to be successfull. This function is exposed so it
    /// can be utilized in cross-chain transfers of TCO2 where we want to burn the
    /// TCO2 in the source chain but not retire it.
    /// @param account The user for whom to burn TCO2
    /// @param amount The amount to burn.
    function bridgeBurn(address account, uint256 amount)
        external
        virtual
        whenNotPaused
        onlyBridges
    {
        _burn(account, amount);
    }

    /// @notice Mint TCO2 on behalf of a user. This function is exposed to
    /// be called by authorized message bridge systems and utilized for
    /// cross-chain transfers of TCO2 where we want to mint the TCO2 in the
    /// source chain.
    /// @param account The user for whom to mint TCO2
    /// @param amount The amount to mint.
    function bridgeMint(address account, uint256 amount)
        external
        virtual
        whenNotPaused
        onlyBridges
    {
        _mint(account, amount);
    }

    // ----------------------------------------
    //       Permissionless functions
    // ----------------------------------------

    function projectVintageTokenId() external view returns (uint256) {
        return _projectVintageTokenId;
    }

    /// @notice Token name getter overriden to return the a name based on the carbon project data
    //slither-disable-next-line external-function
    function name() public view virtual override returns (string memory) {
        string memory globalProjectId;
        string memory vintageName;
        (globalProjectId, vintageName) = getGlobalProjectVintageIdentifiers();
        return
            string(
                abi.encodePacked(
                    'Toucan Protocol: TCO2-',
                    globalProjectId,
                    '-',
                    vintageName
                )
            );
    }

    /// @notice Token symbol getter overriden to return the a symbol based on the carbon project data
    //slither-disable-next-line external-function
    function symbol() public view virtual override returns (string memory) {
        string memory globalProjectId;
        string memory vintageName;
        (globalProjectId, vintageName) = getGlobalProjectVintageIdentifiers();
        return
            string(
                abi.encodePacked('TCO2-', globalProjectId, '-', vintageName)
            );
    }

    /// @dev Helper function to retrieve data fragments for `name()` and `symbol()`
    function getGlobalProjectVintageIdentifiers()
        public
        view
        virtual
        returns (string memory, string memory)
    {
        ProjectData memory projectData;
        VintageData memory vintageData;
        (projectData, vintageData) = getAttributes();
        return (projectData.projectId, vintageData.name);
    }

    /// @dev Function to get corresponding attributes from the CarbonProjects
    function getAttributes()
        public
        view
        virtual
        returns (ProjectData memory, VintageData memory)
    {
        address pc = IToucanContractRegistry(contractRegistry)
            .carbonProjectsAddress();
        address vc = IToucanContractRegistry(contractRegistry)
            .carbonProjectVintagesAddress();

        VintageData memory vintageData = ICarbonProjectVintages(vc)
            .getProjectVintageDataByTokenId(_projectVintageTokenId);
        ProjectData memory projectData = ICarbonProjects(pc)
            .getProjectDataByTokenId(vintageData.projectTokenId);

        return (projectData, vintageData);
    }

    /// @dev Returns the remaining space in TCO2 contract before hitting the cap
    function getRemaining() public view returns (uint256 remaining) {
        uint256 cap = getDepositCap();
        remaining = cap - totalSupply();
    }

    /// @dev Returns the cap for TCO2s based on `totalVintageQuantity`
    /// Returns `~unlimited` if the value for the vintage is not set
    function getDepositCap() public view returns (uint256) {
        VintageData memory vintageData;
        (, vintageData) = getAttributes();
        uint64 totalVintageQuantity = vintageData.totalVintageQuantity;

        ///@dev multipliying tonnes with decimals
        uint256 cap = totalVintageQuantity * 10**decimals();

        /// @dev if totalVintageQuantity is not set (=0), remove cap
        if (cap == 0) return type(uint256).max;

        return cap;
    }

    /// @notice Burn TCO2 on behalf of a user. msg.sender needs to be approved by
    /// the account for the burn to be successfull. This function is exposed so it
    /// can be utilized to burn credits without retiring them (eg. dispose HFC-23).
    /// @param account The user for whom to burn TCO2
    /// @param amount The amount to burn
    function burnFrom(address account, uint256 amount)
        external
        virtual
        whenNotPaused
    {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // @dev Internal function for the burning of TCO2 tokens
    // @dev retiringEntityAddress is a parameter to handle scenarios, when
    // retirements are performed from the escrow contract and the retiring entity
    // is different than the account.
    function _retire(
        address account,
        uint256 amount,
        address retiringEntityAddress
    ) internal virtual returns (uint256 retirementEventId) {
        _burn(account, amount);

        // Register retirement event in the certificates contract
        address certAddr = IToucanContractRegistry(contractRegistry)
            .retirementCertificatesAddress();
        retirementEventId = IRetirementCertificates(certAddr).registerEvent(
            retiringEntityAddress,
            _projectVintageTokenId,
            amount,
            false
        );

        emit Retired(retiringEntityAddress, amount, retirementEventId);
    }

    // @dev Internal function retire and mint certificates
    function _retireAndMintCertificate(
        address retiringEntity,
        CreateRetirementRequestParams memory params
    ) internal virtual whenNotPaused {
        // Retire provided amount
        uint256 retirementEventId = _retire(
            msg.sender,
            params.amount,
            retiringEntity
        );
        uint256[] memory retirementEventIds = new uint256[](1);
        retirementEventIds[0] = retirementEventId;

        //slither-disable-next-line unused-return
        IRetirementCertificates(
            IToucanContractRegistry(contractRegistry)
                .retirementCertificatesAddress()
        ).mintCertificateWithExtraData(
                retiringEntity,
                params,
                retirementEventIds
            );
    }

    // -----------------------------
    //      Locked ERC20 safety
    // -----------------------------

    /// @dev Modifier to disallowing sending tokens to either the 0-address
    /// or this contract itself
    modifier validDestination(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        validDestination(recipient)
        whenNotPaused
        returns (bool)
    {
        super.transfer(recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        virtual
        override
        validDestination(recipient)
        whenNotPaused
        returns (bool)
    {
        super.transferFrom(sender, recipient, amount);
        return true;
    }

    /// @notice Return the name of the registry that this
    /// factory is enabling to tokenize, eg., verra
    /// @dev this must be overridden in the child contract
    function standardRegistry() public virtual returns (string memory) {}
}
