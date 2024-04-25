// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol';

import '../bases/RoleInitializer.sol';
import '../interfaces/IToucanContractRegistry.sol';
import '../interfaces/ICarbonProjects.sol';
import '../interfaces/ICarbonProjectVintages.sol';
import '../libraries/ProjectUtils.sol';
import '../libraries/ProjectVintageUtils.sol';
import '../libraries/Strings.sol';
import '../libraries/Modifiers.sol';
import '../ToucanCarbonOffsetsFactoryStorage.sol';

/// @notice This TCO2 factory base should be used for any logic specific implementation
abstract contract ToucanCarbonOffsetsFactoryBase is
    ToucanCarbonOffsetsFactoryStorageV1,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ProjectUtils,
    ProjectVintageUtils,
    Modifiers,
    ToucanCarbonOffsetsFactoryStorage,
    RoleInitializer
{
    using Strings for string;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev divider to calculate fees in basis points
    uint256 public constant bridgeFeeDivider = 1e4;

    /// @dev All roles related to accessing this contract
    bytes32 public constant DETOKENIZER_ROLE = keccak256('DETOKENIZER_ROLE');
    bytes32 public constant TOKENIZER_ROLE = keccak256('TOKENIZER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event TokenCreated(uint256 vintageTokenId, address tokenAddress);
    event AddedToAllowedBridges(address account);
    event RemovedFromallowedBridges(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __ToucanCarbonOffsetsFactoryBase_init(
        address[] calldata accounts,
        bytes32[] calldata roles
    ) internal {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __RoleInitializer_init_unchained(accounts, roles);
    }

    // ----------------------------------------
    //           Admin functions
    // ----------------------------------------

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    /// @dev sets the Beacon that tracks the current implementation logic of the TCO2s
    function setBeacon(address _beacon) external virtual onlyOwner {
        beacon = _beacon;
    }

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), only Admin
    function pause() external virtual onlyBy(contractRegistry, owner()) {
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() external virtual onlyBy(contractRegistry, owner()) {
        _unpause();
    }

    /// @dev set the registry contract to be tracked
    function setToucanContractRegistry(address _address)
        external
        virtual
        onlyOwner
    {
        contractRegistry = _address;
    }

    /// @notice adds account to the allowedBridges list
    /// meant to be used only for cross-chain bridging
    function addToAllowedBridges(address account) external virtual onlyOwner {
        bool isAllowed = allowedBridges[account];
        require(!isAllowed, 'Already allowed');

        allowedBridges[account] = true;
        emit AddedToAllowedBridges(account);
    }

    /// @notice removes account from the allowedBridges list
    /// meant to be used only for cross-chain bridging
    function removeFromAllowedBridges(address account)
        external
        virtual
        onlyOwner
    {
        bool isAllowed = allowedBridges[account];
        require(isAllowed, 'Already not allowed');

        allowedBridges[account] = false;
        emit RemovedFromallowedBridges(account);
    }

    // ----------------------------------------
    //       Permissionless functions
    // ----------------------------------------

    /// @notice internal factory function to deploy new TCO2 (ERC20) contracts
    /// @dev the function creates a new BeaconProxy for each TCO2
    /// @param projectVintageTokenId links the vintage-specific data to the TCO2 contract
    function deployNewProxy(uint256 projectVintageTokenId)
        internal
        virtual
        whenNotPaused
    {
        require(beacon != address(0), 'Error: Beacon for proxy not set');
        require(
            !checkExistence(projectVintageTokenId),
            'pvERC20 already exists'
        );
        checkProjectVintageTokenExists(contractRegistry, projectVintageTokenId);

        /// Ensure that the TCO2 to be deployed is for a standard that is supported
        /// by the standard registry.
        require(hasValidStandard(projectVintageTokenId), 'Invalid standard');

        /// @dev generate payload for initialize function
        string memory signature = 'initialize(string,string,uint256,address)';
        bytes memory payload = abi.encodeWithSignature(
            signature,
            'Toucan Protocol: TCO2',
            'TCO2',
            projectVintageTokenId,
            contractRegistry
        );

        //slither-disable-next-line reentrancy-no-eth
        BeaconProxy proxyTCO2 = new BeaconProxy(beacon, payload);

        IToucanContractRegistry(contractRegistry).addERC20(
            address(proxyTCO2),
            standardRegistry()
        );

        deployedContracts.push(address(proxyTCO2));
        pvIdtoERC20[projectVintageTokenId] = address(proxyTCO2);

        emit TokenCreated(projectVintageTokenId, address(proxyTCO2));
    }

    /// @dev Deploys a TCO2 contract based on a project vintage
    /// @param projectVintageTokenId numeric tokenId from vintage in `CarbonProjectVintages`
    function deployFromVintage(uint256 projectVintageTokenId)
        external
        virtual
        whenNotPaused
    {
        deployNewProxy(projectVintageTokenId);
    }

    /// @dev Checks if same project vintage has already been deployed
    function checkExistence(uint256 projectVintageTokenId)
        internal
        view
        virtual
        returns (bool)
    {
        if (pvIdtoERC20[projectVintageTokenId] == address(0)) {
            return false;
        } else {
            return true;
        }
    }

    function hasValidStandard(uint256 projectVintageTokenId)
        internal
        view
        returns (bool)
    {
        // Fetch contracts from contract registry
        address tcnRegistry = contractRegistry;
        address pc = IToucanContractRegistry(tcnRegistry)
            .carbonProjectsAddress();
        address vc = IToucanContractRegistry(tcnRegistry)
            .carbonProjectVintagesAddress();

        // Fetch carbon data
        VintageData memory vintageData = ICarbonProjectVintages(vc)
            .getProjectVintageDataByTokenId(projectVintageTokenId);
        ProjectData memory projectData = ICarbonProjects(pc)
            .getProjectDataByTokenId(vintageData.projectTokenId);

        // Check whether standard in carbon data matches supported standards
        // in the current factory
        string[] memory standards = supportedStandards();
        uint256 supportedStandardsLen = standards.length;
        string memory candidateStandard = projectData.standard;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < supportedStandardsLen; ) {
            string memory supportedStandard = standards[i];

            if (candidateStandard.equals(supportedStandard)) {
                return true;
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }

    /// @dev Returns all addresses of deployed TCO2 contracts
    function getContracts() external view virtual returns (address[] memory) {
        return deployedContracts;
    }

    function bridgeFeeReceiverAddress()
        external
        view
        virtual
        returns (address)
    {
        return bridgeFeeReceiver;
    }

    function getBridgeFeeAndBurnAmount(uint256 _quantity)
        external
        view
        virtual
        returns (uint256, uint256)
    {
        //slither-disable-next-line divide-before-multiply
        uint256 feeAmount = (_quantity * bridgeFeePercentageInBase) /
            bridgeFeeDivider;
        //slither-disable-next-line divide-before-multiply
        uint256 burnAmount = (feeAmount * bridgeFeeBurnPercentageInBase) /
            bridgeFeeDivider;
        return (feeAmount, burnAmount);
    }

    /// @notice Update the bridge fee percentage
    /// @param _bridgeFeePercentageInBase percentage of bridge fee in base
    function setBridgeFeePercentage(uint256 _bridgeFeePercentageInBase)
        external
        virtual
        onlyOwner
    {
        require(
            _bridgeFeePercentageInBase < bridgeFeeDivider,
            'bridge fee percentage must be lower than bridge fee divider'
        );
        bridgeFeePercentageInBase = _bridgeFeePercentageInBase;
    }

    /// @notice Update the bridge fee receiver
    /// @param _bridgeFeeReceiver address to transfer the fees
    function setBridgeFeeReceiver(address _bridgeFeeReceiver)
        external
        virtual
        onlyOwner
    {
        bridgeFeeReceiver = _bridgeFeeReceiver;
    }

    /// @notice Update the bridge fee burning percentage
    /// @param _bridgeFeeBurnPercentageInBase percentage of bridge fee in base
    function setBridgeFeeBurnPercentage(uint256 _bridgeFeeBurnPercentageInBase)
        external
        virtual
        onlyOwner
    {
        require(
            _bridgeFeeBurnPercentageInBase < bridgeFeeDivider,
            'burn fee percentage must be lower than bridge fee divider'
        );
        bridgeFeeBurnPercentageInBase = _bridgeFeeBurnPercentageInBase;
    }

    /// @notice Update the bridge fee burn address
    /// @param _bridgeFeeBurnAddress address to transfer the fees to burn
    function setBridgeFeeBurnAddress(address _bridgeFeeBurnAddress)
        external
        virtual
        onlyOwner
    {
        bridgeFeeBurnAddress = _bridgeFeeBurnAddress;
    }

    /// @notice Return the name of the registry that this
    /// factory is enabling to tokenize, eg., verra
    /// @dev this must be overridden in the child contract
    function standardRegistry() public pure virtual returns (string memory) {}

    /// @notice Return the standard(s) supported by the carbon
    /// registry from where this factory tokenizes credits, eg., VCS
    /// It's important to satisfy this interface in order to ensure
    /// that TCO2 factories cannot create TCO2s for standards that
    /// the standard registry does not support
    function supportedStandards()
        public
        pure
        virtual
        returns (string[] memory)
    {}
}
