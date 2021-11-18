// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity ^0.8.0;

import 'hardhat/console.sol'; // dev & testing
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './../IToucanContractRegistry.sol';
import './../ICarbonOffsetBatches.sol';
import './../ToucanCarbonOffsets.sol';
import './BaseCarbonTonneStorage.sol';

/// @notice Base Carbon Tonne for KlimaDAO
/// Contract is an ERC20 compliant token that acts as a pool for TCO2 tokens
/// It is possible to whitelist Toucan Protocol external tokenized carbon
contract BaseCarbonTonne is
    ContextUpgradeable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    BaseCarbonTonneStorage
{
    using SafeERC20 for IERC20;

    event Deposited(address erc20Addr, uint256 amount);
    event Redeemed(address account, address erc20, uint256 amount);

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(uint64 _minimumVintageStartTime)
        public
        virtual
        initializer
    {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ERC20_init_unchained('Toucan Protocol: Base Carbon Tonne', 'BCT');
        setMinimumVintageStartTime(_minimumVintageStartTime);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

    /// @dev modifier that only lets the contract's owner and granted pausers pause the system
    modifier onlyPausers() {
        require(
            hasRole(PAUSER_ROLE, msg.sender) || owner() == msg.sender,
            'Caller is not authorized'
        );
        _;
    }

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), only Admin
    function pause() public virtual onlyPausers {
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() public virtual onlyPausers {
        _unpause();
    }

    function setToucanContractRegistry(address _address)
        public
        virtual
        onlyOwner
    {
        contractRegistry = _address;
    }

    /// @dev WIP: Generic function to switch attributes mappings into either
    /// acceptance or rejection criteria
    /// @param _mappingName attribute mapping of project-vintage data
    /// @param accepted determines if mapping works as black or whitelist
    function switchMapping(string memory _mappingName, bool accepted)
        public
        virtual
        onlyOwner
    {
        if (strcmp(_mappingName, 'regions')) {
            accepted
                ? regionsIsAcceptedMapping = true
                : regionsIsAcceptedMapping = false;
        } else if (strcmp(_mappingName, 'standards')) {
            accepted
                ? standardsIsAcceptedMapping = true
                : standardsIsAcceptedMapping = false;
        } else if (strcmp(_mappingName, 'methodologies')) {
            accepted
                ? methodologiesIsAcceptedMapping = true
                : methodologiesIsAcceptedMapping = false;
        }
    }

    /// @notice function to add attributes for filtering (does not support complex AttributeSets)
    /// @param addToList determines whether attribute should be added or removed
    /// Other params are arrays of attributes to be added
    function addAttributes(
        bool addToList,
        string[] memory _regions,
        string[] memory _standards,
        string[] memory _methodologies
    ) public virtual onlyOwner {
        uint256 standardsLen = _standards.length;
        if (standardsLen > 0) {
            for (uint256 i = 0; i < standardsLen; i++) {
                if (addToList == true) {
                    standards[_standards[i]] = true;
                } else {
                    standards[_standards[i]] = false;
                }
            }
        }

        uint256 methodologiesLen = _methodologies.length;
        if (methodologiesLen > 0) {
            for (uint256 i = 0; i < methodologiesLen; i++) {
                if (addToList == true) {
                    methodologies[_methodologies[i]] = true;
                } else {
                    methodologies[_methodologies[i]] = false;
                }
            }
        }

        uint256 regionsLen = _regions.length;
        if (regionsLen > 0) {
            for (uint256 i = 0; i < regionsLen; i++) {
                if (addToList == true) {
                    regions[_regions[i]] = true;
                } else {
                    regions[_regions[i]] = false;
                }
            }
        }
    }

    /// @dev whitelist selected external non-TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToExternalWhiteList(address[] memory erc20Addr)
        public
        onlyOwner
    {
        uint256 addrLen = erc20Addr.length;

        for (uint256 i = 0; i < addrLen; i++) {
            externalWhiteList[erc20Addr[i]] = true;
        }
    }

    /// @dev whitelist certain TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToInternalWhiteList(address[] memory erc20Addr)
        public
        onlyOwner
    {
        uint256 addrLen = erc20Addr.length;

        for (uint256 i = 0; i < addrLen; i++) {
            // @TODO check isContract
            internalWhiteList[erc20Addr[i]] = true;
        }
    }

    /// @dev blacklist certain TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToInternalBlackList(address[] memory erc20Addr)
        public
        onlyOwner
    {
        uint256 addrLen = erc20Addr.length;

        for (uint256 i = 0; i < addrLen; i++) {
            // @TODO check isContract
            internalBlackList[erc20Addr[i]] = true;
        }
    }

    /// @dev remove ERC20 addresses from external whitelist
    /// @param erc20Addr accepts an array of contract addresses
    function removeFromExternalWhiteList(address[] memory erc20Addr)
        public
        onlyOwner
    {
        uint256 addrLen = erc20Addr.length;

        for (uint256 i = 0; i < addrLen; i++) {
            externalWhiteList[erc20Addr[i]] = false;
        }
    }

    /// @dev remove TCO2 addresses from internal blacklist
    /// @param erc20Addr accepts an array of contract addresses
    function removeFromInternalBlackList(address[] memory erc20Addr)
        public
        onlyOwner
    {
        uint256 addrLen = erc20Addr.length;

        for (uint256 i = 0; i < addrLen; i++) {
            internalBlackList[erc20Addr[i]] = false;
        }
    }

    /// @dev remove TCO2 addresses from internal whitelist
    /// @param erc20Addr accepts an array of contract addressesc
    function removeFromInternalWhiteList(address[] memory erc20Addr)
        public
        onlyOwner
    {
        uint256 addrLen = erc20Addr.length;

        for (uint256 i = 0; i < addrLen; i++) {
            internalWhiteList[erc20Addr[i]] = false;
        }
    }

    /// @dev function to limit the maximum supply for security reasons
    /// supplyCap is initially set to 0 and must be increased before deposits
    function setSupplyCap(uint256 newCap) external virtual onlyOwner {
        supplyCap = newCap;
    }

    /// @dev determines the minimum vintage (similar to year) of TCO2s
    /// @param _minimumVintageStartTime unix time format
    function setMinimumVintageStartTime(uint64 _minimumVintageStartTime)
        public
        virtual
        onlyOwner
    {
        minimumVintageStartTime = _minimumVintageStartTime;
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice deposit function for BCT pool that accepts TCTs and mints BCT 1:1
    /// @param erc20Addr ERC20 contract address to be deposited, requires approve
    /// Eligibility is checked via `checkEligible`, logic can be external
    function deposit(address erc20Addr, uint256 amount)
        public
        virtual
        whenNotPaused
    {
        require(checkEligible(erc20Addr), 'Token rejected');

        uint256 remainingSpace = getRemaining();
        require(remainingSpace > 0, 'Error: Cannot deposit, Pool is full');

        if (amount > remainingSpace) amount = remainingSpace;

        IERC20(erc20Addr).safeTransferFrom(msg.sender, address(this), amount);

        // Increasing balance sheet of individual token and overall
        tokenBalances[erc20Addr] += amount;
        // mints pool/index token to prev. owner(sender)
        _mint(msg.sender, amount);
        emit Deposited(erc20Addr, amount);
    }

    /// @notice Internal function that checks if token to be deposited is eligible for this pool
    function checkEligible(address erc20Addr)
        internal
        view
        virtual
        returns (bool)
    {
        bool isToucanContract = IToucanContractRegistry(contractRegistry)
            .checkERC20(erc20Addr);

        if (isToucanContract) {
            if (internalWhiteList[erc20Addr]) {
                return true;
            }

            require(
                internalBlackList[erc20Addr] == false,
                'Error: TCO2 token contract blacklisted'
            );

            require(
                checkAttributeMatching(erc20Addr) == true,
                'Error: TCO2 token contract rejected, non-matching attributes'
            );
        }
        // If not Toucan native contract, check if address is whitelisted
        else {
            require(
                externalWhiteList[erc20Addr] == true,
                'Error: External carbon credit token not whitelisted'
            );
            return true;
        }

        return true;
    }

    /// @notice checks whether incoming project-vintage-ERC20 token matches the accepted criteria/attributes
    function checkAttributeMatching(address erc20Addr)
        public
        view
        virtual
        returns (bool)
    {
        ProjectData memory projectData;
        VintageData memory vintageData;
        (projectData, vintageData) = ToucanCarbonOffsets(erc20Addr)
            .getAttributes();

        /// @dev checks if any one of the attributes are blacklisted.
        // If mappings are set to "whitelist"-mode, require the opposite
        require(
            vintageData.startTime >= minimumVintageStartTime,
            "Vintage starts before pool's minimum vintage start time"
        );
        require(
            regions[projectData.region] == regionsIsAcceptedMapping,
            'Project region failed acceptance test'
        );
        require(
            standards[projectData.standard] == standardsIsAcceptedMapping,
            'Project standard failed acceptance test'
        );
        require(
            methodologies[projectData.methodology] ==
                methodologiesIsAcceptedMapping,
            'Project methodology failed acceptance test'
        );

        return true;
    }

    /// @notice Redeems Pool tokens for multiple underlying pERC20s 1:1
    /// User specifies in front-end the addresses and amounts they want
    /// Pool token in User's wallet get burned
    function redeemMany(address[] memory erc20s, uint256[] memory amounts)
        public
        virtual
        whenNotPaused
    {
        uint256 addrLen = erc20s.length;
        uint256 amountsLen = amounts.length;
        require(addrLen == amountsLen, 'Error: Length of arrays not matching');

        for (uint256 i = 0; i < addrLen; i++) {
            redeemSingle(msg.sender, erc20s[i], amounts[i]);
        }
    }

    // Redeems a single underlying token
    function redeemSingle(
        address account,
        address erc20,
        uint256 amount
    ) internal virtual whenNotPaused {
        require(msg.sender == account, 'Only own funds can be redeemed');
        require(
            tokenBalances[erc20] >= amount,
            'Cannot redeem more than is stored in contract'
        );
        _burn(account, amount);
        tokenBalances[erc20] -= amount;
        IERC20(erc20).safeTransfer(account, amount);
        emit Redeemed(account, erc20, amount);
    }

    // Redeem, and call offset on underlying contracts
    // Note: Not yet implemented
    // function offset(uint256 amount) public virtual whenNotPaused {}

    // Implemented in order to disable transfers when paused
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), 'ERC20Pausable: token transfer while paused');
    }

    /// @dev Returns the remaining space in pool before hitting the cap
    function getRemaining() public view returns (uint256) {
        return (supplyCap - totalSupply());
    }

    // -----------------------------
    //      Locked ERC20 safety
    // -----------------------------

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
        returns (bool)
    {
        super.transfer(recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override validDestination(recipient) returns (bool) {
        super.transferFrom(sender, recipient, amount);
        return true;
    }

    // -----------------------------
    //      Helper Functions
    // -----------------------------
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
}
