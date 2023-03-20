// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './interfaces/IPausable.sol';
import './interfaces/IToucanContractRegistry.sol';
import './ToucanContractRegistryStorage.sol';

/// @dev The ToucanContractRegistry is queried by other contracts for current addresses
contract ToucanContractRegistry is
    ToucanContractRegistryStorage,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    IToucanContractRegistry,
    UUPSUpgradeable
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

    // ----------------------------------------
    //      Modifiers
    // ----------------------------------------

    modifier onlyBy(address _factory, address _owner) {
        require(
            _factory == _msgSender() || _owner == _msgSender(),
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

    /// @notice security function that pauses all contracts part of the carbon bri  dge
    function pauseSystem() external onlyPausers {
        IPausable cpv = IPausable(_carbonProjectVintagesAddress);
        if (!cpv.paused()) cpv.pause();

        IPausable cp = IPausable(_carbonProjectsAddress);
        if (!cp.paused()) cp.pause();

        IPausable cob = IPausable(_carbonOffsetBatchesAddress);
        if (!cob.paused()) cob.pause();

        IPausable tcof = IPausable(_toucanCarbonOffsetsFactoryAddress);
        if (!tcof.paused()) tcof.pause();
    }

    function unpauseSystem() external onlyOwner {
        IPausable cpv = IPausable(_carbonProjectVintagesAddress);
        if (cpv.paused()) cpv.unpause();

        IPausable cp = IPausable(_carbonProjectsAddress);
        if (cp.paused()) cp.unpause();

        IPausable cob = IPausable(_carbonOffsetBatchesAddress);
        if (cob.paused()) cob.unpause();

        IPausable tcof = IPausable(_toucanCarbonOffsetsFactoryAddress);
        if (tcof.paused()) tcof.unpause();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize() external virtual initializer {
        __Ownable_init();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        /// @dev granting the deployer==owner the rights to grant other roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
        virtual
        onlyOwner
    {
        require(_address != address(0), 'Error: zero address provided');
        _carbonOffsetBatchesAddress = _address;
    }

    function setCarbonProjectsAddress(address _address)
        external
        virtual
        onlyOwner
    {
        require(_address != address(0), 'Error: zero address provided');
        _carbonProjectsAddress = _address;
    }

    function setCarbonProjectVintagesAddress(address _address)
        external
        virtual
        onlyOwner
    {
        require(_address != address(0), 'Error: zero address provided');
        _carbonProjectVintagesAddress = _address;
    }

    function setToucanCarbonOffsetsFactoryAddress(address _address)
        external
        virtual
        onlyOwner
    {
        require(_address != address(0), 'Error: zero address provided');
        _toucanCarbonOffsetsFactoryAddress = _address;
    }

    function setCarbonOffsetBadgesAddress(address _address)
        external
        virtual
        onlyOwner
    {
        require(_address != address(0), 'Error: zero address provided');
        _carbonOffsetBadgesAddress = _address;
    }

    /// @dev function to add valid TCO2 contracts
    function addERC20(address _address)
        external
        virtual
        override
        onlyBy(_toucanCarbonOffsetsFactoryAddress, owner())
    {
        projectVintageERC20Registry[_address] = true;
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

    function toucanCarbonOffsetsFactoryAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _toucanCarbonOffsetsFactoryAddress;
    }

    function carbonOffsetBadgesAddress()
        external
        view
        virtual
        override
        returns (address)
    {
        return _carbonOffsetBadgesAddress;
    }

    function checkERC20(address _address)
        external
        view
        virtual
        override
        returns (bool)
    {
        return projectVintageERC20Registry[_address];
    }
}
