// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import '../cross-chain/interfaces/IToucanCrosschainMessenger.sol';
import '../interfaces/IPoolFilter.sol';
import '../interfaces/IToucanCarbonOffsets.sol';
import '../libraries/Errors.sol';
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
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.6.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @dev All roles related to accessing this contract
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');

    /// @dev divider to calculate fees in basis points
    uint256 public constant feeRedeemDivider = 1e4;

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event Deposited(address erc20Addr, uint256 amount);
    event Redeemed(address account, address erc20, uint256 amount);
    event RedeemFeePaid(address redeemer, uint256 fees);
    event RedeemFeeBurnt(address redeemer, uint256 fees);
    event RedeemFeeUpdated(uint256 feeBp);
    event RedeemRetireFeeUpdated(uint256 feeBp);
    event SupplyCapUpdated(uint256 newCap);
    event FilterUpdated(address filter);
    event TCO2ScoringUpdated(address[] tco2s);
    event AddFeeExemptedTCO2(address tco2);
    event RemoveFeeExemptedTCO2(address tco2);
    event RouterUpdated(address router);
    event TCO2Bridged(
        uint32 indexed destinationDomain,
        address indexed tco2,
        uint256 amount
    );

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
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address) internal virtual override {
        onlyPoolOwner();
    }

    // ------------------------
    // Poor person's modifiers
    // ------------------------

    /// @dev function that checks whether the caller is the
    /// contract owner
    function onlyPoolOwner() internal view virtual {
        require(owner() == msg.sender, Errors.CP_ONLY_OWNER);
    }

    /// @dev function that only lets the contract's owner and granted role to execute
    function onlyWithRole(bytes32 role) internal view virtual {
        require(
            hasRole(role, msg.sender) || owner() == msg.sender,
            Errors.CP_UNAUTHORIZED
        );
    }

    /// @dev function that checks whether the contract is paused
    function onlyUnpaused() internal view {
        require(!paused(), Errors.CP_PAUSED_CONTRACT);
    }

    // ------------------------
    //      Admin functions
    // ------------------------

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), only Admin
    function pause() external virtual {
        onlyWithRole(PAUSER_ROLE);
        _pause();
    }

    /// @dev unpause the system, wraps _unpause(), only Admin
    function unpause() external virtual {
        onlyWithRole(PAUSER_ROLE);
        _unpause();
    }

    /// @notice Update the fee redeem percentage
    /// @param _feeBp percentage of fee in basis points
    function setFeeRedeemPercentage(uint256 _feeBp) external virtual {
        onlyWithRole(MANAGER_ROLE);
        require(_feeBp < feeRedeemDivider, Errors.CP_INVALID_FEE);
        feeRedeemPercentageInBase = _feeBp;
        emit RedeemFeeUpdated(_feeBp);
    }

    /// @notice Update the fee percentage charged in redeemManyAndRetire
    /// @param _feeBp percentage of fee in basis points
    function setFeeRedeemRetirePercentage(uint256 _feeBp) external virtual {
        onlyWithRole(MANAGER_ROLE);
        require(_feeBp < feeRedeemDivider, Errors.CP_INVALID_FEE);
        feeRedeemRetirePercentageInBase = _feeBp;
        emit RedeemRetireFeeUpdated(_feeBp);
    }

    /// @notice Update the fee redeem receiver
    /// @param _feeRedeemReceiver address to transfer the fees
    function setFeeRedeemReceiver(address _feeRedeemReceiver) external virtual {
        onlyPoolOwner();
        require(_feeRedeemReceiver != address(0), Errors.CP_EMPTY_ADDRESS);
        feeRedeemReceiver = _feeRedeemReceiver;
    }

    /// @notice Update the fee redeem burn percentage
    /// @param _feeRedeemBurnPercentageInBase percentage of fee in base
    function setFeeRedeemBurnPercentage(uint256 _feeRedeemBurnPercentageInBase)
        external
        virtual
    {
        onlyPoolOwner();
        require(
            _feeRedeemBurnPercentageInBase < feeRedeemDivider,
            Errors.CP_INVALID_FEE
        );
        feeRedeemBurnPercentageInBase = _feeRedeemBurnPercentageInBase;
    }

    /// @notice Update the fee redeem burn address
    /// @param _feeRedeemBurnAddress address to transfer the fees to burn
    function setFeeRedeemBurnAddress(address _feeRedeemBurnAddress)
        external
        virtual
    {
        onlyPoolOwner();
        require(_feeRedeemBurnAddress != address(0), Errors.CP_EMPTY_ADDRESS);
        feeRedeemBurnAddress = _feeRedeemBurnAddress;
    }

    /// @notice Adds a new address for redeem fees exemption
    /// @param _address address to be exempted on redeem fees
    function addRedeemFeeExemptedAddress(address _address) external virtual {
        onlyPoolOwner();
        redeemFeeExemptedAddresses[_address] = true;
    }

    /// @notice Removes an address from redeem fees exemption
    /// @param _address address to be removed from exemption
    function removeRedeemFeeExemptedAddress(address _address) external virtual {
        onlyPoolOwner();
        redeemFeeExemptedAddresses[_address] = false;
    }

    /// @notice Adds a new TCO2 for redeem fees exemption
    /// @param _tco2 TCO2 to be exempted on redeem fees
    function addRedeemFeeExemptedTCO2(address _tco2) external virtual {
        onlyPoolOwner();
        redeemFeeExemptedTCO2s[_tco2] = true;
        emit AddFeeExemptedTCO2(_tco2);
    }

    /// @notice Removes a TCO2 from redeem fees exemption
    /// @param _tco2 TCO2 to be removed from exemption
    function removeRedeemFeeExemptedTCO2(address _tco2) external virtual {
        onlyPoolOwner();
        redeemFeeExemptedTCO2s[_tco2] = false;
        emit RemoveFeeExemptedTCO2(_tco2);
    }

    /// @notice Function to limit the maximum BCT supply
    /// @dev supplyCap is initially set to 0 and must be increased before deposits
    function setSupplyCap(uint256 newCap) external virtual {
        onlyPoolOwner();
        supplyCap = newCap;
        emit SupplyCapUpdated(newCap);
    }

    /// @notice Update the address of the filter contract
    /// @param _filter Filter contract address
    function setFilter(address _filter) external virtual {
        onlyPoolOwner();
        filter = _filter;
        emit FilterUpdated(_filter);
    }

    /// @notice Allows MANAGERs or the owner to pass an array to hold TCO2 contract addesses that are
    /// ordered by some form of scoring mechanism
    /// @param tco2s array of ordered TCO2 addresses
    function setTCO2Scoring(address[] calldata tco2s) external {
        onlyWithRole(MANAGER_ROLE);
        require(tco2s.length != 0, Errors.CP_EMPTY_ARRAY);
        scoredTCO2s = tco2s;
        emit TCO2ScoringUpdated(tco2s);
    }

    // -------------------------------------
    //   ToucanCrosschainMessenger functions
    // -------------------------------------

    function onlyRouter() internal view {
        require(msg.sender == router, Errors.CP_ONLY_ROUTER);
    }

    /// @notice method to set router address
    /// @dev use this method to set router address
    /// @param _router address of ToucanCrosschainMessenger
    function setRouter(address _router) external {
        onlyPoolOwner();
        // router address can be set to zero to make bridgeMint and bridgeBurn unusable
        router = _router;
        emit RouterUpdated(_router);
    }

    /// @notice mint tokens to receiver account that were cross-chain bridged
    /// @dev invoked only by the ToucanCrosschainMessenger (Router)
    /// @param _account account that will be minted with corss-chain bridged tokens
    /// @param _amount amount of tokens that will be minted
    function bridgeMint(address _account, uint256 _amount) external {
        onlyRouter();
        _mint(_account, _amount);
    }

    /// @notice burn tokens from account to be cross-chain bridged
    /// @dev invoked only by the ToucanCrosschainMessenger (Router)
    /// @param _account account that will be burned with corss-chain bridged tokens
    /// @param _amount amount of tokens that will be burned
    function bridgeBurn(address _account, uint256 _amount) external {
        onlyRouter();
        _burn(_account, _amount);
    }

    /// @notice Allows MANAGER or the owner to bridge TCO2s into
    /// another domain.
    /// @param destinationDomain The domain to bridge TCO2s to
    /// @param tco2s The TCO2s to bridge
    /// @param amounts The amounts of TCO2s to bridge
    function bridgeTCO2s(
        uint32 destinationDomain,
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external {
        onlyWithRole(MANAGER_ROLE);
        uint256 tco2Length = tco2s.length;
        require(tco2Length != 0, Errors.CP_EMPTY_ARRAY);
        require(tco2Length == amounts.length, Errors.CP_LENGTH_MISMATCH);

        // TODO: Disallow bridging more TCO2s than an amount that
        // would bring the pool to imbalance, ie., end up with more
        // pool tokens than TCO2s in the pool in the source chain.

        // Read the address of the remote pool from ToucanCrosschainMessenger
        // and set that as a recipient in our cross-chain messages.
        address tcm = router;
        RemoteTokenInformation memory remoteInfo = IToucanCrosschainMessenger(
            tcm
        ).remoteTokens(address(this), destinationDomain);
        address recipient = remoteInfo.tokenAddress;
        require(recipient != address(0), Errors.CP_EMPTY_ADDRESS);

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
            IToucanCrosschainMessenger(tcm).sendMessageWithRecipient(
                destinationDomain,
                tco2s[i],
                amounts[i],
                recipient
            );
            emit TCO2Bridged(destinationDomain, tco2s[i], amounts[i]);
        }
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice Deposit function for BCT pool that accepts TCO2s and mints BCT 1:1
    /// @param erc20Addr ERC20 contract address to be deposited, requires approve
    /// @dev Eligibility is checked via `checkEligible`, balances are tracked
    /// for each TCO2 separately
    function deposit(address erc20Addr, uint256 amount) external virtual {
        onlyUnpaused();
        require(checkEligible(erc20Addr), Errors.CP_NOT_ELIGIBLE);

        uint256 remainingSpace = getRemaining();
        require(remainingSpace != 0, Errors.CP_FULL_POOL);

        if (amount > remainingSpace) amount = remainingSpace;

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
        return IPoolFilter(filter).checkEligible(erc20Addr);
    }

    /// @notice Returns minimum vintage start time for this pool
    function minimumVintageStartTime() external view returns (uint64) {
        return IPoolFilter(filter).minimumVintageStartTime();
    }

    /// @notice Checks if region is eligible for this pool
    function regions(string calldata region) external view returns (bool) {
        return IPoolFilter(filter).regions(region);
    }

    /// @notice Checks if standard is eligible for this pool
    function standards(string calldata standard) external view returns (bool) {
        return IPoolFilter(filter).standards(standard);
    }

    /// @notice Checks if methodology is eligible for this pool
    function methodologies(string calldata methodology)
        external
        view
        returns (bool)
    {
        return IPoolFilter(filter).methodologies(methodology);
    }

    /// @notice View function to calculate fees pre-execution
    /// @dev User specifies in front-end the addresses and amounts they want
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// @return Total fees amount
    function calculateRedeemFees(
        address[] memory tco2s,
        uint256[] memory amounts
    ) external view virtual returns (uint256) {
        onlyUnpaused();
        if (redeemFeeExemptedAddresses[msg.sender]) {
            return 0;
        }
        uint256 tco2Length = tco2s.length;
        require(tco2Length == amounts.length, Errors.CP_LENGTH_MISMATCH);

        //slither-disable-next-line uninitialized-local
        uint256 totalFee;
        uint256 _feeRedeemPercentageInBase = feeRedeemPercentageInBase;

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
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
    function redeemAndBurn(address tco2, uint256 amount) external {
        onlyUnpaused();
        require(redeemFeeExemptedTCO2s[tco2], Errors.CP_NOT_EXEMPTED);
        redeemSingle(tco2, amount);
        // User has to approve the pool contract in the TCO2 contract
        // in order for this function to successfully burn the tokens
        IToucanCarbonOffsets(tco2).burnFrom(msg.sender, amount);
    }

    /// @notice Redeems pool tokens for multiple underlying TCO2s 1:1 minus fees
    /// The redeemed TCO2s are retired in the same go in order to allow charging
    /// a lower fee vs selective redemptions that do not retire the TCO2s.
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem and retire for each tco2s
    /// @return retirementIds The retirements ids that were produced
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemAndRetireMany(
        address[] memory tco2s,
        uint256[] memory amounts
    )
        external
        virtual
        returns (
            uint256[] memory retirementIds,
            uint256[] memory redeemedAmounts
        )
    {
        (retirementIds, redeemedAmounts) = redeemManyInternal(
            tco2s,
            amounts,
            true
        );
    }

    /// @notice Redeems pool tokens for multiple underlying TCO2s 1:1 minus fees
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of amounts to redeem for each tco2s
    /// Pool token in user's wallet get burned
    /// @return redeemedAmounts The amounts of the TCO2s that were redeemed
    function redeemMany(address[] memory tco2s, uint256[] memory amounts)
        external
        virtual
        returns (uint256[] memory redeemedAmounts)
    {
        (, redeemedAmounts) = redeemManyInternal(tco2s, amounts, false);
    }

    function redeemManyInternal(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    )
        internal
        returns (
            uint256[] memory retirementIds,
            uint256[] memory redeemedAmounts
        )
    {
        onlyUnpaused();
        uint256 tco2Length = tco2s.length;
        require(tco2Length == amounts.length, Errors.CP_LENGTH_MISMATCH);

        //slither-disable-next-line uninitialized-local
        uint256 totalFee;
        //slither-disable-next-line uninitialized-local
        uint256 _feeRedeemPercentageInBase;
        if (toRetire) {
            retirementIds = new uint256[](tco2Length);
            _feeRedeemPercentageInBase = feeRedeemRetirePercentageInBase;
        } else {
            _feeRedeemPercentageInBase = feeRedeemPercentageInBase;
        }
        bool isExempted = redeemFeeExemptedAddresses[msg.sender];
        //slither-disable-next-line uninitialized-local
        uint256 feeAmount;
        redeemedAmounts = new uint256[](tco2Length);

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ) {
            checkEligible(tco2s[i]);
            if (!isExempted) {
                feeAmount =
                    (amounts[i] * _feeRedeemPercentageInBase) /
                    feeRedeemDivider;
                totalFee += feeAmount;
            } else {
                feeAmount = 0;
            }

            // Redeem the amount minus the fee
            uint256 amountToRedeem = amounts[i] - feeAmount;
            redeemSingle(tco2s[i], amountToRedeem);

            // If requested, retire the TCO2s in one go. Callers should
            // first approve the pool in order for the pool to retire
            // on behalf of them
            if (toRetire) {
                retirementIds[i] = IToucanCarbonOffsets(tco2s[i]).retireFrom(
                    msg.sender,
                    amountToRedeem
                );
            }
            redeemedAmounts[i] = amountToRedeem;

            unchecked {
                ++i;
            }
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
    function redeemAuto(uint256 amount)
        external
        virtual
        returns (address[] memory tco2s, uint256[] memory amounts)
    {
        return redeemAuto2(amount);
    }

    /// @notice Automatically redeems an amount of Pool tokens for underlying
    /// TCO2s from an array of ranked TCO2 contracts starting from contract at
    /// index 0 until amount is satisfied.
    /// @param amount Total amount to be redeemed
    /// @return tco2s amounts The addresses and amounts of the TCO2s that were
    /// automatically redeemed
    function redeemAuto2(uint256 amount)
        public
        virtual
        returns (address[] memory tco2s, uint256[] memory amounts)
    {
        onlyUnpaused();
        require(amount != 0, Errors.CP_ZERO_AMOUNT);
        //slither-disable-next-line uninitialized-local
        uint256 i;
        // Non-zero count tracks TCO2s with a balance
        //slither-disable-next-line uninitialized-local
        uint256 nonZeroCount;

        uint256 scoredTCO2Len = scoredTCO2s.length;
        while (amount > 0 && i < scoredTCO2Len) {
            address tco2 = scoredTCO2s[i];
            uint256 balance = tokenBalances(tco2);
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
            //slither-disable-next-line incorrect-equality
            if (amount == 0) {
                tco2s = new address[](nonZeroCount);
                amounts = new uint256[](nonZeroCount);

                tco2s[nonZeroCount - 1] = tco2;
                amounts[nonZeroCount - 1] = amountToRedeem;
                redeemSingle(tco2, amountToRedeem);
            }
        }

        require(amount == 0, Errors.CP_NON_ZERO_REMAINING);

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
            uint256 balance = tokenBalances(tco2);

            // Ignore empty balances so we don't generate redundant transactions.
            //slither-disable-next-line incorrect-equality
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
    function redeemSingle(address erc20, uint256 amount) internal virtual {
        _burn(msg.sender, amount);
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

        onlyUnpaused();
    }

    /// @dev Returns the remaining space in pool before hitting the cap
    function getRemaining() public view returns (uint256) {
        return (supplyCap - totalSupply());
    }

    /// @notice Returns the balance of the TCO2 found in the pool
    function tokenBalances(address tco2) public view returns (uint256) {
        return IERC20Upgradeable(tco2).balanceOf(address(this));
    }

    // -----------------------------
    //      Locked ERC20 safety
    // -----------------------------

    /// @dev Function to disallowing sending tokens to either the 0-address
    /// or this contract itself
    function validDestination(address to) internal view {
        require(to != address(0x0), Errors.CP_INVALID_DESTINATION_ZERO);
        require(to != address(this), Errors.CP_INVALID_DESTINATION_SELF);
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        validDestination(recipient);
        super.transfer(recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        validDestination(recipient);
        super.transferFrom(sender, recipient, amount);
        return true;
    }

    function getScoredTCO2s() external view returns (address[] memory) {
        return scoredTCO2s;
    }
}
