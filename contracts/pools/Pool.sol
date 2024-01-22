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
import {FeeDistribution, IFeeCalculator} from './interfaces/IFeeCalculator.sol';
import '../interfaces/IPoolFilter.sol';
import '../interfaces/IToucanCarbonOffsets.sol';
import '../libraries/Errors.sol';
import './PoolStorage.sol';

/// @notice Pool template contract
/// ERC20 compliant token that acts as a pool for TCO2 tokens
abstract contract Pool is
    ContextUpgradeable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PoolStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

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
    event DepositFeePaid(address depositor, uint256 fees);
    event RedeemFeePaid(address redeemer, uint256 fees);
    event RedeemFeeBurnt(address redeemer, uint256 fees);
    event RedeemFeeExempted(address exemptedUser, bool isExempted);
    event SupplyCapUpdated(uint256 newCap);
    event FilterUpdated(address filter);
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
    // Admin functions
    // ------------------------

    /// @notice Emergency function to disable contract's core functionality
    /// @dev wraps _pause(), only Admin
    function pause() external virtual {
        onlyWithRole(PAUSER_ROLE);
        _pause();
    }

    /// @dev Unpause the system, wraps _unpause(), only Admin
    function unpause() external virtual {
        onlyWithRole(PAUSER_ROLE);
        _unpause();
    }

    /// @notice Adds a new address for redeem fees exemption
    /// @param _address address to be exempted on redeem fees
    function addRedeemFeeExemptedAddress(address _address) external virtual {
        onlyPoolOwner();
        redeemFeeExemptedAddresses[_address] = true;
        emit RedeemFeeExempted(_address, true);
    }

    /// @notice Removes an address from redeem fees exemption
    /// @param _address address to be removed from exemption
    function removeRedeemFeeExemptedAddress(address _address) external virtual {
        onlyPoolOwner();
        redeemFeeExemptedAddresses[_address] = false;
        emit RedeemFeeExempted(_address, false);
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

    /// @notice Function to limit the maximum pool supply
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

    function _getRemotePoolAddress(address tcm, uint32 destinationDomain)
        internal
        view
        returns (address recipient)
    {
        RemoteTokenInformation memory remoteInfo = IToucanCrosschainMessenger(
            tcm
        ).remoteTokens(address(this), destinationDomain);
        recipient = remoteInfo.tokenAddress;
        require(recipient != address(0), Errors.CP_EMPTY_ADDRESS);
    }

    /// @notice Get the fee needed to bridge TCO2s into the destination domain.
    /// @param destinationDomain The domain to bridge TCO2s to
    /// @param tco2s The TCO2s to bridge
    /// @param amounts The amounts of TCO2s to bridge
    /// @return fee The fee amount to be paid
    function quoteBridgeTCO2sFee(
        uint32 destinationDomain,
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external view returns (uint256 fee) {
        uint256 tco2Length = tco2s.length;
        require(tco2Length == amounts.length, Errors.CP_LENGTH_MISMATCH);

        address tcm = router;
        address recipient = _getRemotePoolAddress(tcm, destinationDomain);

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
            fee += IToucanCrosschainMessenger(tcm).quoteTokenTransferFee(
                destinationDomain,
                tco2s[i],
                amounts[i],
                recipient
            );
        }
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
    ) external payable {
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
        address recipient = _getRemotePoolAddress(tcm, destinationDomain);

        uint256 payment = msg.value / tco2Length;
        uint256 tempSupply = _totalTCO2Supply;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
            tempSupply -= amounts[i];
            //slither-disable-next-line reentrancy-eth
            IToucanCrosschainMessenger(tcm).transferTokensToRecipient{
                value: payment
            }(destinationDomain, tco2s[i], amounts[i], recipient);
            emit TCO2Bridged(destinationDomain, tco2s[i], amounts[i]);
        }
        _totalTCO2Supply = tempSupply;
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    function _deposit(
        address erc20Addr,
        uint256 amount,
        uint256 maxFee
    ) internal returns (uint256 mintedPoolTokenAmount) {
        onlyUnpaused();

        // Ensure the TCO2 is eligible to be deposited
        _checkEligible(erc20Addr);

        // Ensure there is space in the pool
        uint256 remainingSpace = getRemaining();
        require(remainingSpace != 0, Errors.CP_FULL_POOL);

        // If the amount to be deposited exceeds the remaining space, deposit
        // the maximum amount possible up to the cap instead of failing.
        if (amount > remainingSpace) amount = remainingSpace;

        uint256 depositedAmount = amount;
        if (feeCalculator != IFeeCalculator(address(0))) {
            // If a fee module is configured, use it to calculate the minting fees
            FeeDistribution memory feeDistribution = feeCalculator
                .calculateDepositFees(
                    erc20Addr,
                    address(this),
                    depositedAmount
                );
            uint256 feeDistributionTotal = getFeeDistributionTotal(
                feeDistribution
            );
            if (maxFee != 0) {
                // Protect caller against getting charged a higher fee than expected
                require(feeDistributionTotal <= maxFee, Errors.CP_FEE_TOO_HIGH);
            }
            depositedAmount -= feeDistributionTotal;

            // Distribute the fee between the recipients
            uint256 recipientLen = feeDistribution.recipients.length;
            for (uint256 i = 0; i < recipientLen; ++i) {
                _mint(feeDistribution.recipients[i], feeDistribution.shares[i]);
            }
            emit DepositFeePaid(msg.sender, feeDistributionTotal);
        }

        // Mint pool tokens to the user
        _mint(msg.sender, depositedAmount);
        _totalTCO2Supply += amount;
        emit Deposited(erc20Addr, amount);

        // Transfer the TCO2 to the pool
        IERC20Upgradeable(erc20Addr).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        return depositedAmount;
    }

    function calculateDepositFees(address tco2, uint256 amount)
        external
        view
        returns (uint256 feeDistributionTotal)
    {
        onlyUnpaused();

        IFeeCalculator feeCalc = feeCalculator;
        if (address(feeCalc) == address(0)) {
            // No deposit fees charged if no fee module is configured
            return 0;
        }
        FeeDistribution memory feeDistribution = feeCalc.calculateDepositFees(
            tco2,
            address(this),
            amount
        );
        feeDistributionTotal = getFeeDistributionTotal(feeDistribution);
    }

    /// @notice Checks if token to be deposited is eligible for this pool.
    /// Reverts if not.
    /// Beware that the revert reason might depend on the underlying implementation
    /// of IPoolFilter.checkEligible
    /// @param erc20Addr the contract to check
    /// @return isEligible true if address is eligible and no other issues occur
    function checkEligible(address erc20Addr)
        external
        view
        virtual
        returns (bool isEligible)
    {
        _checkEligible(erc20Addr);

        return true;
    }

    function _checkEligible(address erc20Addr) internal view {
        //slither-disable-next-line unused-return
        try IPoolFilter(filter).checkEligible(erc20Addr) returns (
            //slither-disable-next-line uninitialized-local
            bool isEligible
        ) {
            require(isEligible, Errors.CP_NOT_ELIGIBLE);
            //slither-disable-next-line uninitialized-local
        } catch Error(string memory reason) {
            revert(reason);
            //slither-disable-next-line uninitialized-local
        } catch (bytes memory reason) {
            // this most often results in a random bytes sequence,
            // but it's worth at least trying to log it
            revert(
                string(abi.encodePacked('unexpected error: ', string(reason)))
            );
        }
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
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionFees(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    ) public view virtual returns (uint256 feeDistributionTotal) {
        onlyUnpaused();

        // Exempted addresses pay no fees
        if (redeemFeeExemptedAddresses[msg.sender]) {
            return 0;
        }

        uint256 tco2Length = tco2s.length;
        require(tco2Length == amounts.length, Errors.CP_LENGTH_MISMATCH);

        for (uint256 i = 0; i < tco2Length; ++i) {
            if (feeCalculator == IFeeCalculator(address(0))) {
                feeDistributionTotal += getFixedRedemptionFee(
                    amounts[i],
                    toRetire
                );
            } else {
                FeeDistribution memory feeDistribution = feeCalculator
                    .calculateRedemptionFees(
                        tco2s[i],
                        address(this),
                        amounts[i]
                    );
                feeDistributionTotal += getFeeDistributionTotal(
                    feeDistribution
                );
            }
        }
    }

    function getFeeDistributionTotal(FeeDistribution memory feeDistribution)
        internal
        pure
        returns (uint256 feeAmount)
    {
        uint256 recipientLen = feeDistribution.recipients.length;
        //slither-disable-next-line incorrect-equality
        require(
            recipientLen == feeDistribution.shares.length,
            Errors.CP_LENGTH_MISMATCH
        );
        for (uint256 i = 0; i < recipientLen; ++i) {
            feeAmount += feeDistribution.shares[i];
        }
        return feeAmount;
    }

    function calculateRedemptionFee(
        address tco2,
        uint256 amount,
        bool toRetire
    ) internal view returns (FeeDistribution memory feeDistribution) {
        if (feeCalculator == IFeeCalculator(address(0))) {
            // Fall back to fixed fee if a fee module is not configured
            uint256 feeAmount = getFixedRedemptionFee(amount, toRetire);
            return getFixedRedemptionFeeRecipients(feeAmount);
        }

        // Use the fee module if one is configured
        return
            feeCalculator.calculateRedemptionFees(tco2, address(this), amount);
    }

    function getFixedRedemptionFee(uint256 amount, bool toRetire)
        internal
        view
        returns (uint256)
    {
        // Use appropriate fee bp to charge
        uint256 feeBp = 0;
        if (toRetire) {
            feeBp = _feeRedeemRetirePercentageInBase;
        } else {
            feeBp = _feeRedeemPercentageInBase;
        }
        // Calculate fee
        return (amount * feeBp) / feeRedeemDivider;
    }

    function getFixedRedemptionFeeRecipients(uint256 totalFee)
        internal
        view
        returns (FeeDistribution memory feeDistribution)
    {
        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);
        recipients[0] = _feeRedeemReceiver;
        shares[0] = totalFee;
        return FeeDistribution(recipients, shares);
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

    function _redeemMany(
        address[] memory tco2s,
        uint256[] memory amounts,
        uint256 maxFee,
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

        // Initialize return arrays
        redeemedAmounts = new uint256[](tco2Length);
        if (toRetire) {
            retirementIds = new uint256[](tco2Length);
        }

        // Exempted addresses pay no fees
        bool isExempted = redeemFeeExemptedAddresses[msg.sender];

        // Execute redemptions
        uint256 totalFee = 0;
        for (uint256 i = 0; i < tco2Length; ++i) {
            _checkEligible(tco2s[i]);

            uint256 amountToRedeem = amounts[i];
            if (!isExempted) {
                // Calculate the fee to be paid for the current TCO2 redemption
                FeeDistribution memory feeDistribution = calculateRedemptionFee(
                    tco2s[i],
                    amounts[i],
                    toRetire
                );
                uint256 feeDistributionTotal = getFeeDistributionTotal(
                    feeDistribution
                );
                amountToRedeem -= feeDistributionTotal;
                totalFee += feeDistributionTotal;

                // Distribute the fee between the recipients
                distributeRedemptionFee(
                    feeDistribution.recipients,
                    feeDistribution.shares
                );
            }

            // Redeem the amount minus the fee
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

            // Keep track of redeemed amounts in return arguments
            // to make the function composable.
            redeemedAmounts[i] = amountToRedeem;
        }

        if (maxFee != 0) {
            // Protect caller against getting charged a higher fee than expected
            require(totalFee <= maxFee, Errors.CP_FEE_TOO_HIGH);
        }
    }

    // Distribute the fees between the recipients
    function distributeRedemptionFee(
        address[] memory recipients,
        uint256[] memory fees
    ) internal {
        uint256 amountToBurn = 0;
        for (uint256 i = 0; i < recipients.length; ++i) {
            uint256 fee = fees[i];
            uint256 burnAmount = (fee * _feeRedeemBurnPercentageInBase) /
                feeRedeemDivider;
            fee -= burnAmount;
            amountToBurn += burnAmount;
            transfer(recipients[i], fee);
            emit RedeemFeePaid(msg.sender, fee);
        }
        if (amountToBurn > 0) {
            transfer(_feeRedeemBurnAddress, amountToBurn);
            emit RedeemFeeBurnt(msg.sender, amountToBurn);
        }
    }

    /// @dev Internal function that redeems a single underlying token
    function redeemSingle(address erc20, uint256 amount) internal virtual {
        _burn(msg.sender, amount);
        IERC20Upgradeable(erc20).safeTransfer(msg.sender, amount);
        _totalTCO2Supply -= amount;
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
}
