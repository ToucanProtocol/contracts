// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

// ============ External Imports ============
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol';

// ============ Internal Imports ============
import './interfaces/IToucanContractRegistry.sol';
import './interfaces/ICarbonOffsetBatches.sol';
import './libraries/ProjectUtils.sol';
import './libraries/ProjectVintageUtils.sol';
import './libraries/Modifiers.sol';
import './ToucanCarbonOffsets.sol';
import './ToucanCarbonOffsetsFactoryStorage.sol';

/// @notice This TCO2 factory creates project-vintage-specific ERC20 contracts for Batch-NFT fractionalization
/// Locks in received ERC721 Batch-NFTs and can mint corresponding quantity of ERC20s
/// Permissionless, anyone can deploy new ERC20s unless they do not yet exist and pid exists
//slither-disable-next-line unprotected-upgrade
contract ToucanCarbonOffsetsFactory is
    ToucanCarbonOffsetsFactoryStorageV1,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ProjectUtils,
    ProjectVintageUtils,
    Modifiers,
    ToucanCarbonOffsetsFactoryStorage
{
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    uint256 public constant bridgeFeeDivider = 1e4;

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event TokenCreated(uint256 vintageTokenId, address tokenAddress);
    event AddedToAllowlist(address account);
    event RemovedFromAllowlist(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    /// @dev Returns the current version of the smart contract
    function version() external pure returns (string memory) {
        return '1.2.0';
    }

    function initialize(address _contractRegistry)
        external
        virtual
        initializer
    {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        contractRegistry = _contractRegistry;
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

    /// @notice adds account to the allowlist
    /// meant to be used only for cross-chain bridging
    function addToAllowlist(address account) external virtual onlyOwner {
        bool isAllowed = allowlist[account];
        require(!isAllowed, 'Already allowed');

        allowlist[account] = true;
        emit AddedToAllowlist(account);
    }

    /// @notice removes account from the allowlist
    /// meant to be used only for cross-chain bridging
    function removeFromAllowlist(address account) external virtual onlyOwner {
        bool isAllowed = allowlist[account];
        require(isAllowed, 'Already not allowed');

        allowlist[account] = false;
        emit RemovedFromAllowlist(account);
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

        IToucanContractRegistry(contractRegistry).addERC20(address(proxyTCO2));

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

    function increaseTotalRetired(uint256 amount) external {
        bool isTCO2 = IToucanContractRegistry(contractRegistry).checkERC20(
            msg.sender
        );
        require(isTCO2 || msg.sender == owner(), 'Invalid sender');
        totalRetired += amount;
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
}
