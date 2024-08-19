// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './bases/RoleInitializer.sol';
import './interfaces/IPausable.sol';
import './interfaces/IToucanCarbonOffsetsFactory.sol';
import './interfaces/IToucanContractRegistry.sol';
import './libraries/Strings.sol';
import './ToucanContractRegistryStorage.sol';

/// @dev The ToucanContractRegistry is queried by other contracts for current addresses
contract ToucanContractRegistry is
    ToucanContractRegistryStorageLegacy,
    OwnableUpgradeable,
    RoleInitializer,
    IToucanContractRegistry,
    UUPSUpgradeable,
    ToucanContractRegistryStorage
{
    using Strings for string;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.3.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @dev All roles related to accessing this contract
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event TCO2FactoryAdded(address indexed factory, string indexed standard);

    // ----------------------------------------
    //      Modifiers
    // ----------------------------------------

    modifier onlyBy(address _factory, address _owner) {
        require(
            _factory == msg.sender || _owner == msg.sender,
            'Caller is not the factory'
        );
        _;
    }

    /// @dev modifier that only lets the contract's owner and granted pausers pause the system
    modifier onlyPausers() {
        require(
            hasRole(PAUSER_ROLE, msg.sender) || owner() == msg.sender,
            'Caller is not authorized'
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice security function that pauses all contracts part of the carbon bridge
    function pauseSystem() external onlyPausers {
        IPausable cpv = IPausable(_carbonProjectVintagesAddress);
        if (!cpv.paused()) cpv.pause();

        IPausable cp = IPausable(_carbonProjectsAddress);
        if (!cp.paused()) cp.pause();

        IPausable cob = IPausable(_carbonOffsetBatchesAddress);
        if (!cob.paused()) cob.pause();

        uint256 standardRegistriesLen = standardRegistries.length;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < standardRegistriesLen; ) {
            string memory standardRegistry = standardRegistries[i];
            address factory = toucanCarbonOffsetFactories[standardRegistry];

            IPausable tcof = IPausable(factory);
            if (!tcof.paused()) tcof.pause();

            unchecked {
                ++i;
            }
        }
    }

    /// @notice security function that unpauses all contracts part of the carbon bridge
    function unpauseSystem() external onlyOwner {
        IPausable cpv = IPausable(_carbonProjectVintagesAddress);
        if (cpv.paused()) cpv.unpause();

        IPausable cp = IPausable(_carbonProjectsAddress);
        if (cp.paused()) cp.unpause();

        IPausable cob = IPausable(_carbonOffsetBatchesAddress);
        if (cob.paused()) cob.unpause();

        uint256 standardRegistriesLen = standardRegistries.length;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < standardRegistriesLen; ) {
            string memory standardRegistry = standardRegistries[i];
            address factory = toucanCarbonOffsetFactories[standardRegistry];

            IPausable tcof = IPausable(factory);
            if (tcof.paused()) tcof.unpause();

            unchecked {
                ++i;
            }
        }
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address[] calldata _accounts, bytes32[] calldata _roles)
        external
        virtual
        initializer
    {
        __Ownable_init();
        __RoleInitializer_init_unchained(_accounts, _roles);
        __UUPSUpgradeable_init_unchained();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    // ----------------------------------------
    //              Setters
    // ----------------------------------------
    function setCarbonOffsetBatchesAddress(address _address)
        external
        onlyOwner
    {
        require(_address != address(0), 'Zero address');
        _carbonOffsetBatchesAddress = _address;
    }

    function setCarbonProjectsAddress(address _address) external onlyOwner {
        require(_address != address(0), 'Zero address');
        _carbonProjectsAddress = _address;
    }

    function setCarbonProjectVintagesAddress(address _address)
        external
        onlyOwner
    {
        require(_address != address(0), 'Zero address');
        _carbonProjectVintagesAddress = _address;
    }

    function setToucanCarbonOffsetsFactoryAddress(address tco2Factory)
        external
        onlyOwner
    {
        require(tco2Factory != address(0), 'Zero address');

        // Get the standard registry from the factory
        string memory standardRegistry = IToucanCarbonOffsetsFactory(
            tco2Factory
        ).standardRegistry();
        require(bytes(standardRegistry).length != 0, 'Empty standard registry');

        if (!standardRegistryExists(standardRegistry)) {
            standardRegistries.push(standardRegistry);
        }
        toucanCarbonOffsetFactories[standardRegistry] = tco2Factory;

        emit TCO2FactoryAdded(tco2Factory, standardRegistry);
    }

    function standardRegistryExists(string memory standard)
        private
        view
        returns (bool)
    {
        uint256 standardRegistriesLen = standardRegistries.length;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < standardRegistriesLen; ) {
            if (standardRegistries[i].equals(standard)) {
                return true;
            }

            unchecked {
                ++i;
            }
        }
        return false;
    }

    function setToucanCarbonOffsetsEscrowAddress(address _address)
        external
        onlyOwner
    {
        require(_address != address(0), 'Zero address');
        _toucanCarbonOffsetsEscrowAddress = _address;
    }

    function setRetirementCertificatesAddress(address _address)
        external
        onlyOwner
    {
        require(_address != address(0), 'Zero address');
        _retirementCertificatesAddress = _address;
    }

    function setRetirementCertificateSlicerAddress(address _address)
        external
        onlyOwner
    {
        require(_address != address(0), 'Zero address');
        _retirementCertificateSlicerAddress = _address;
    }

    function setRetirementCertificateSlicesAddress(address _address)
        external
        onlyOwner
    {
        require(_address != address(0), 'Zero address');
        _retirementCertificateSlicesAddress = _address;
    }

    /// @notice Keep track of TCO2s per standard
    function addERC20(address erc20, string calldata standardRegistry)
        external
        onlyBy(toucanCarbonOffsetFactories[standardRegistry], owner())
    {
        projectVintageERC20Registry[erc20] = true;
    }

    // ----------------------------------------
    //              Getters
    // ----------------------------------------

    function carbonOffsetBatchesAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _carbonOffsetBatchesAddress;
    }

    function carbonProjectsAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _carbonProjectsAddress;
    }

    function carbonProjectVintagesAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _carbonProjectVintagesAddress;
    }

    /// @dev return the TCO2 factory address for the provided standard
    function toucanCarbonOffsetsFactoryAddress(string memory standardRegistry)
        external
        view
        virtual
        override
        returns (address)
    {
        return toucanCarbonOffsetFactories[standardRegistry];
    }

    function toucanCarbonOffsetsEscrowAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _toucanCarbonOffsetsEscrowAddress;
    }

    function retirementCertificatesAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _retirementCertificatesAddress;
    }

    function retirementCertificateSlicerAddress()
        external
        view
        virtual
        returns (address)
    {
        return _retirementCertificateSlicerAddress;
    }

    function retirementCertificateSlicesAddress()
        external
        view
        virtual
        returns (address)
    {
        return _retirementCertificateSlicesAddress;
    }

    /// TODO: Kept for backwards-compatibility; will be removed in a future
    /// upgrade in favor of isValidERC20(erc20)
    function checkERC20(address erc20) external view virtual returns (bool) {
        return projectVintageERC20Registry[erc20];
    }

    function isValidERC20(address erc20)
        external
        view
        virtual
        override
        returns (bool)
    {
        return projectVintageERC20Registry[erc20];
    }

    function supportedStandardRegistries()
        external
        view
        returns (string[] memory)
    {
        return standardRegistries;
    }
}
