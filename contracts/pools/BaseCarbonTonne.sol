// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import '../interfaces/ICarbonOffsetBatches.sol';
import '../interfaces/IToucanCarbonOffsets.sol';
import '../interfaces/IToucanContractRegistry.sol';
import './BaseCarbonTonneStorage.sol';

/// @notice Base Carbon Tonne for KlimaDAO
/// Contract is an ERC20 compliant token that acts as a pool for TCO2 tokens
/// It is possible to whitelist Toucan Protocol external tokenized carbon
//slither-disable-next-line unprotected-upgrade
contract BaseCarbonTonne is
    ContextUpgradeable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    BaseCarbonTonneStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    string public constant VERSION = '1.5.0';
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');
    /// @dev fees redeem percentage with 2 fixed decimals precision
    uint256 public constant feeRedeemDivider = 1e4;

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event Deposited(address erc20Addr, uint256 amount);
    event Redeemed(address account, address erc20, uint256 amount);
    event ExternalAddressWhitelisted(address erc20addr);
    event ExternalAddressRemovedFromWhitelist(address erc20addr);
    event InternalAddressWhitelisted(address erc20addr);
    event InternalAddressBlacklisted(address erc20addr);
    event InternalAddressRemovedFromBlackList(address erc20addr);
    event InternalAddressRemovedFromWhitelist(address erc20addr);
    event AttributeStandardAdded(string standard);
    event AttributeStandardRemoved(string standard);
    event AttributeMethodologyAdded(string methodology);
    event AttributeMethodologyRemoved(string methodology);
    event AttributeRegionAdded(string region);
    event AttributeRegionRemoved(string region);
    event RedeemFeePaid(address redeemer, uint256 fees);
    event RedeemFeeBurnt(address redeemer, uint256 fees);
    event ToucanRegistrySet(address ContractRegistry);
    event MappingSwitched(string mappingName, bool accepted);
    event SupplyCapUpdated(uint256 newCap);
    event MinimumVintageStartTimeUpdated(uint256 minimumVintageStartTime);
    event TCO2ScoringUpdated(address[] tco2s);
    event AddFeeExemptedTCO2(address tco2);
    event RemoveFeeExemptedTCO2(address tco2);
    event RouterUpdated(address router);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize() external virtual initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ERC20_init_unchained('Toucan Protocol: Base Carbon Tonne', 'BCT');
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

    /// @dev modifier that only lets the contract's owner and granted role to execute
    modifier onlyWithRole(bytes32 role) {
        require(
            hasRole(role, msg.sender) || owner() == msg.sender,
            'Unauthorized'
        );
        _;
    }

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), only Admin
    function pause() external virtual onlyWithRole(PAUSER_ROLE) {
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() external virtual onlyWithRole(PAUSER_ROLE) {
        _unpause();
    }

    function setToucanContractRegistry(address _address)
        external
        virtual
        onlyOwner
    {
        contractRegistry = _address;
        emit ToucanRegistrySet(_address);
    }

    /// @notice Generic function to switch attributes mappings into either
    /// acceptance or rejection criteria
    /// @param _mappingName attribute mapping of project-vintage data
    /// @param accepted determines if mapping works as black or whitelist
    function switchMapping(string memory _mappingName, bool accepted)
        external
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
    ) external virtual onlyOwner {
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

    /// @notice Function to whitelist selected external non-TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToExternalWhiteList(address[] memory erc20Addr)
        external
        onlyOwner
    {
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            externalWhiteList[erc20Addr[i]] = true;
            emit ExternalAddressWhitelisted(erc20Addr[i]);
        }
    }

    /// @notice Function to whitelist certain TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToInternalWhiteList(address[] memory erc20Addr)
        external
        onlyOwner
    {
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalWhiteList[erc20Addr[i]] = true;
            emit InternalAddressWhitelisted(erc20Addr[i]);
        }
    }

    /// @notice Function to blacklist certain TCO2 contracts by their address
    /// @param erc20Addr accepts an array of contract addresses
    function addToInternalBlackList(address[] memory erc20Addr)
        external
        onlyOwner
    {
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalBlackList[erc20Addr[i]] = true;
            emit InternalAddressBlacklisted(erc20Addr[i]);
        }
    }

    /// @notice Function to remove ERC20 addresses from external whitelist
    /// @param erc20Addr accepts an array of contract addresses
    function removeFromExternalWhiteList(address[] memory erc20Addr)
        external
        onlyOwner
    {
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            externalWhiteList[erc20Addr[i]] = false;
            emit ExternalAddressRemovedFromWhitelist(erc20Addr[i]);
        }
    }

    /// @notice Function to remove TCO2 addresses from internal blacklist
    /// @param erc20Addr accepts an array of contract addresses
    function removeFromInternalBlackList(address[] memory erc20Addr)
        external
        onlyOwner
    {
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalBlackList[erc20Addr[i]] = false;
            emit InternalAddressRemovedFromBlackList(erc20Addr[i]);
        }
    }

    /// @notice Function to remove TCO2 addresses from internal whitelist
    /// @param erc20Addr accepts an array of contract addressesc
    function removeFromInternalWhiteList(address[] memory erc20Addr)
        external
        onlyOwner
    {
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < erc20Addr.length; ++i) {
            internalWhiteList[erc20Addr[i]] = false;
            emit InternalAddressRemovedFromWhitelist(erc20Addr[i]);
        }
    }

    /// @notice Update the fee redeem percentage
    /// @param _feeRedeemPercentageInBase percentage of fee in base
    function setFeeRedeemPercentage(uint256 _feeRedeemPercentageInBase)
        external
        virtual
        onlyOwner
    {
        require(
            _feeRedeemPercentageInBase < feeRedeemDivider,
            'Invalid fee percentage'
        );
        feeRedeemPercentageInBase = _feeRedeemPercentageInBase;
    }

    /// @notice Update the fee redeem receiver
    /// @param _feeRedeemReceiver address to transfer the fees
    function setFeeRedeemReceiver(address _feeRedeemReceiver)
        external
        virtual
        onlyOwner
    {
        require(_feeRedeemReceiver != address(0), 'Invalid fee address');
        feeRedeemReceiver = _feeRedeemReceiver;
    }

    /// @notice Update the fee redeem burn percentage
    /// @param _feeRedeemBurnPercentageInBase percentage of fee in base
    function setFeeRedeemBurnPercentage(uint256 _feeRedeemBurnPercentageInBase)
        external
        virtual
        onlyOwner
    {
        require(
            _feeRedeemBurnPercentageInBase < feeRedeemDivider,
            'Invalid burn percentage'
        );
        feeRedeemBurnPercentageInBase = _feeRedeemBurnPercentageInBase;
    }

    /// @notice Update the fee redeem burn address
    /// @param _feeRedeemBurnAddress address to transfer the fees to burn
    function setFeeRedeemBurnAddress(address _feeRedeemBurnAddress)
        external
        virtual
        onlyOwner
    {
        require(_feeRedeemBurnAddress != address(0), 'Invalid burn address');
        feeRedeemBurnAddress = _feeRedeemBurnAddress;
    }

    /// @notice Adds a new address for redeem fees exemption
    /// @param _address address to be exempted on redeem fees
    function addRedeemFeeExemptedAddress(address _address)
        external
        virtual
        onlyOwner
    {
        redeemFeeExemptedAddresses[_address] = true;
    }

    /// @notice Removes an address from redeem fees exemption
    /// @param _address address to be removed from exemption
    function removeRedeemFeeExemptedAddress(address _address)
        external
        virtual
        onlyOwner
    {
        redeemFeeExemptedAddresses[_address] = false;
    }

    /// @notice Adds a new TCO2 for redeem fees exemption
    /// @param _tco2 TCO2 to be exempted on redeem fees
    function addRedeemFeeExemptedTCO2(address _tco2)
        external
        virtual
        onlyOwner
    {
        redeemFeeExemptedTCO2s[_tco2] = true;
        emit AddFeeExemptedTCO2(_tco2);
    }

    /// @notice Removes a TCO2 from redeem fees exemption
    /// @param _tco2 TCO2 to be removed from exemption
    function removeRedeemFeeExemptedTCO2(address _tco2)
        external
        virtual
        onlyOwner
    {
        redeemFeeExemptedTCO2s[_tco2] = false;
        emit RemoveFeeExemptedTCO2(_tco2);
    }

    /// @notice Function to limit the maximum BCT supply
    /// @dev supplyCap is initially set to 0 and must be increased before deposits
    function setSupplyCap(uint256 newCap) external virtual onlyOwner {
        supplyCap = newCap;
        emit SupplyCapUpdated(newCap);
    }

    /// @notice Determines the minimum vintage start time acceptance criteria of TCO2s
    /// @param _minimumVintageStartTime unix time format
    function setMinimumVintageStartTime(uint64 _minimumVintageStartTime)
        external
        virtual
        onlyOwner
    {
        minimumVintageStartTime = _minimumVintageStartTime;
        emit MinimumVintageStartTimeUpdated(_minimumVintageStartTime);
    }

    /// @notice Allows MANAGERs or the owner to pass an array to hold TCO2 contract addesses that are
    /// ordered by some form of scoring mechanism
    /// @param tco2s array of ordered TCO2 addresses
    function setTCO2Scoring(address[] calldata tco2s)
        external
        onlyWithRole(MANAGER_ROLE)
    {
        require(tco2s.length > 0, '!tco2s');
        scoredTCO2s = tco2s;
        emit TCO2ScoringUpdated(tco2s);
    }

    /**
     * @notice method to set router address
     * @dev use this method to set router address
     * @param _router address of ToucanCrosschainMessenger
     */
    function setRouter(address _router) external onlyOwner {
        // router address can be set to zero to make bridgeMint and bridgeBurn unusable
        router = _router;
        emit RouterUpdated(_router);
    }

    // -------------------------------------
    //   ToucanCrosschainMessenger functions
    // -------------------------------------

    modifier onlyRouter() {
        require(msg.sender == router, 'Only Router functionality');
        _;
    }

    /**
     * @notice mint tokens to receiver account that were cross-chain bridged
     * @dev invoked only by the ToucanCrosschainMessenger (Router)
     * @param _account account that will be minted with corss-chain bridged tokens
     * @param _amount amount of tokens that will be minted
     */
    function bridgeMint(address _account, uint256 _amount) external onlyRouter {
        _mint(_account, _amount);
    }

    /**
     * @notice burn tokens from account to be cross-chain bridged
     * @dev invoked only by the ToucanCrosschainMessenger (Router)
     * @param _account account that will be burned with corss-chain bridged tokens
     * @param _amount amount of tokens that will be burned
     */
    function bridgeBurn(address _account, uint256 _amount) external onlyRouter {
        _burn(_account, _amount);
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice Deposit function for BCT pool that accepts TCO2s and mints BCT 1:1
    /// @param erc20Addr ERC20 contract address to be deposited, requires approve
    /// @dev Eligibility is checked via `checkEligible`, balances are tracked
    /// for each TCO2 separately
    function deposit(address erc20Addr, uint256 amount)
        external
        virtual
        whenNotPaused
    {
        require(checkEligible(erc20Addr), 'Token rejected');

        uint256 remainingSpace = getRemaining();
        require(remainingSpace > 0, 'Full pool');

        if (amount > remainingSpace) amount = remainingSpace;

        /// @dev Increase balance sheet of individual token
        tokenBalances[erc20Addr] += amount;
        _mint(msg.sender, amount);
        emit Deposited(erc20Addr, amount);

        IERC20Upgradeable(erc20Addr).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    /// @notice Checks if token to be deposited is eligible for this pool
    function checkEligible(address erc20Addr)
        public
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

            require(internalBlackList[erc20Addr] == false, 'Blacklisted TCO2');

            require(
                checkAttributeMatching(erc20Addr) == true,
                'Non-matching attributes'
            );
        }
        /// @dev If not Toucan native contract, check if address is whitelisted
        else {
            require(externalWhiteList[erc20Addr] == true, 'Not whitelisted');
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
        (projectData, vintageData) = IToucanCarbonOffsets(erc20Addr)
            .getAttributes();

        /// @dev checks if any one of the attributes are blacklisted.
        /// If mappings are set to "whitelist"-mode, require the opposite
        require(
            vintageData.startTime >= minimumVintageStartTime,
            'Start time too old'
        );
        require(
            regions[projectData.region] == regionsIsAcceptedMapping,
            'Region not accepted'
        );
        require(
            standards[projectData.standard] == standardsIsAcceptedMapping,
            'Standard not accepted'
        );
        require(
            methodologies[projectData.methodology] ==
                methodologiesIsAcceptedMapping,
            'Methodology not accepted'
        );

        return true;
    }

    /// @notice View function to calculate fees pre-execution
    /// @dev User specifies in front-end the addresses and amounts they want
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// @return Total fees amount
    function calculateRedeemFees(
        address[] memory tco2s,
        uint256[] memory amounts
    ) external view virtual whenNotPaused returns (uint256) {
        if (redeemFeeExemptedAddresses[msg.sender]) {
            return 0;
        }
        require(tco2s.length == amounts.length, 'Length of arrays differ');

        //slither-disable-next-line uninitialized-local
        uint256 totalFee;
        uint256 _feeRedeemPercentageInBase = feeRedeemPercentageInBase;

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2s.length; ++i) {
            uint256 feeAmount = (amounts[i] * _feeRedeemPercentageInBase) /
                feeRedeemDivider;
            totalFee += feeAmount;
        }
        return totalFee;
    }

    /// @notice Redeem a whitelisted TCO2 without paying any fees and burn
    /// the TCO2. Initially added to burn HFC-23 credits, can be used in the
    /// future to dispose of any other whitelisted credits.
    /// @dev User needs to approve the pool contract in the TCO2 contract for
    /// the amount to be burnt before executing this function.
    /// @param tco2 TCO2 to redeem and burn
    /// @param amount Amount to redeem and burn
    function redeemAndBurn(address tco2, uint256 amount)
        external
        whenNotPaused
    {
        require(redeemFeeExemptedTCO2s[tco2], 'Not exempted');
        redeemSingle(tco2, amount);
        // User has to approve the pool contract in the TCO2 contract
        // in order for this function to successfully burn the tokens
        IToucanCarbonOffsets(tco2).burnFrom(msg.sender, amount);
    }

    /// @notice Redeems Pool tokens for multiple underlying TCO2s 1:1 minus fees
    /// @dev User specifies in front-end the addresses and amounts they want
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// BCT Pool token in user's wallet get burned
    function redeemMany(address[] memory tco2s, uint256[] memory amounts)
        external
        virtual
        whenNotPaused
    {
        uint256 tco2Length = tco2s.length;
        require(tco2Length == amounts.length, 'Length of arrays differ');

        //slither-disable-next-line uninitialized-local
        uint256 totalFee;
        uint256 _feeRedeemPercentageInBase = feeRedeemPercentageInBase;
        bool isExempted = redeemFeeExemptedAddresses[msg.sender];
        //slither-disable-next-line uninitialized-local
        uint256 feeAmount;

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
            if (!isExempted) {
                feeAmount =
                    (amounts[i] * _feeRedeemPercentageInBase) /
                    feeRedeemDivider;
                totalFee += feeAmount;
            } else {
                feeAmount = 0;
            }
            redeemSingle(tco2s[i], amounts[i] - feeAmount);
        }
        if (totalFee != 0) {
            uint256 burnAmount = (totalFee * feeRedeemBurnPercentageInBase) /
                feeRedeemDivider;
            totalFee -= burnAmount;
            transfer(feeRedeemReceiver, totalFee);
            emit RedeemFeePaid(msg.sender, totalFee);
            if (burnAmount > 0) {
                transfer(feeRedeemBurnAddress, burnAmount);
                emit RedeemFeeBurnt(msg.sender, burnAmount);
            }
        }
    }

    /// @notice Automatically redeems an amount of Pool tokens for underlying
    /// TCO2s from an array of ranked TCO2 contracts
    /// starting from contract at index 0 until amount is satisfied
    /// @param amount Total amount to be redeemed
    /// @dev BCT Pool tokens in user's wallet get burned
    function redeemAuto(uint256 amount) external virtual whenNotPaused {
        //slither-disable-next-line uninitialized-local
        uint256 i;

        uint256 scoredTCO2Len = scoredTCO2s.length;
        while (amount > 0 && i < scoredTCO2Len) {
            address tco2 = scoredTCO2s[i];
            uint256 balance = tokenBalances[tco2];

            // Only TCO2s with a balance should be included for a redemption.
            if (balance != 0) {
                uint256 amountToRedeem = amount > balance ? balance : amount;
                redeemSingle(tco2, amountToRedeem);
                amount -= amountToRedeem;
            }

            unchecked {
                i += 1;
            }
        }

        require(amount == 0, 'Non-zero remaining amount');
    }

    /// @notice Automatically redeems an amount of Pool tokens for underlying
    /// TCO2s from an array of ranked TCO2 contracts starting from contract at
    /// index 0 until amount is satisfied. redeemAuto2 is slightly more expensive
    /// than redeemAuto but it is going to be more optimal to use by other on-chain
    /// contracts.
    /// @param amount Total amount to be redeemed
    /// @return tco2s amounts The addresses and amounts of the TCO2s that were
    /// automatically redeemed
    function redeemAuto2(uint256 amount)
        external
        virtual
        whenNotPaused
        returns (address[] memory tco2s, uint256[] memory amounts)
    {
        //slither-disable-next-line uninitialized-local
        uint256 i;
        // Non-zero count tracks TCO2s with a balance
        //slither-disable-next-line uninitialized-local
        uint256 nonZeroCount;

        uint256 scoredTCO2Len = scoredTCO2s.length;
        while (amount > 0 && i < scoredTCO2Len) {
            address tco2 = scoredTCO2s[i];
            uint256 balance = tokenBalances[tco2];
            //slither-disable-next-line uninitialized-local
            uint256 amountToRedeem;

            // Only TCO2s with a balance should be included for a redemption.
            if (balance != 0) {
                amountToRedeem = amount > balance ? balance : amount;
                amount -= amountToRedeem;
                unchecked {
                    ++nonZeroCount;
                }
            }

            unchecked {
                ++i;
            }

            // Create return arrays statically since Solidity does not
            // support dynamic arrays or mappings in-memory (EIP-1153).
            // Do it here to avoid having to fill out the last indexes
            // during the second iteration.
            if (amount == 0) {
                tco2s = new address[](nonZeroCount);
                amounts = new uint256[](nonZeroCount);

                tco2s[nonZeroCount - 1] = tco2;
                amounts[nonZeroCount - 1] = amountToRedeem;
                redeemSingle(tco2, amountToRedeem);
            }
        }

        require(amount == 0, 'Non-zero remaining amount');

        // Execute the second iteration by avoiding to run the last index
        // since we have already executed that in the first iteration.
        nonZeroCount = 0;
        //slither-disable-next-line uninitialized-local
        for (uint256 j; j < i - 1; ++j) {
            address tco2 = scoredTCO2s[j];
            // This second loop only gets called when the `amount` is larger
            // than the first tco2 balance in the array. Here, in every iteration the
            // tco2 balance is smaller than the remaining amount while the last bit of
            // the `amount` which is smaller than the tco2 balance, got redeemed
            // in the first loop.
            uint256 balance = tokenBalances[tco2];

            // Ignore empty balances so we don't generate redundant transactions.
            if (balance == 0) continue;

            tco2s[nonZeroCount] = tco2;
            amounts[nonZeroCount] = balance;
            redeemSingle(tco2, balance);
            unchecked {
                ++nonZeroCount;
            }
        }
    }

    /// @dev Internal function that redeems a single underlying token
    function redeemSingle(address erc20, uint256 amount)
        internal
        virtual
        whenNotPaused
    {
        require(tokenBalances[erc20] >= amount, 'Amount exceeds supply');
        _burn(msg.sender, amount);
        tokenBalances[erc20] -= amount;
        IERC20Upgradeable(erc20).safeTransfer(msg.sender, amount);
        emit Redeemed(msg.sender, erc20, amount);
    }

    /// @dev Implemented in order to disable transfers when paused
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), 'Paused contract');
    }

    /// @dev Returns the remaining space in pool before hitting the cap
    function getRemaining() public view returns (uint256) {
        return (supplyCap - totalSupply());
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

    function getScoredTCO2s() external view returns (address[] memory) {
        return scoredTCO2s;
    }
}
