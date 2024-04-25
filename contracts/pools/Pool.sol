// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {FeeDistribution, IFeeCalculator} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

import '../bases/RoleInitializer.sol';
import '../interfaces/IPoolFilter.sol';
import '../interfaces/IToucanCarbonOffsets.sol';
import {Errors} from '../libraries/Errors.sol';
import './PoolStorage.sol';

/// @notice Pool template contract
/// ERC20 compliant token that acts as a pool for vintage tokens
abstract contract Pool is
    ContextUpgradeable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    RoleInitializer,
    UUPSUpgradeable,
    PoolStorage
{
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
    event RedeemBurnFeeUpdated(uint256 feeBp);
    event RedeemFeeBurnAddressUpdated(address receiver);
    event RedeemFeeExempted(address exemptedUser, bool isExempted);
    event SupplyCapUpdated(uint256 newCap);
    event FilterUpdated(address filter);
    event AddFeeExemptedTCO2(address tco2);
    event RemoveFeeExemptedTCO2(address tco2);

    struct PoolVintageToken {
        address vintageToken;
        // This field only makes sense for ERC-1155 tokens
        uint256 erc1155VintageTokenId;
        // This field is meant to separate projects for both
        // ERC-20 and ERC-1155 tokens.
        uint256 projectTokenId;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __Pool_init_unchained(
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
    //                Abstract
    // ----------------------------------------

    function _increaseSupply(PoolVintageToken memory vintage, int256 delta)
        internal
        virtual;

    function _feeDistribution(PoolVintageToken memory vintage, uint256)
        internal
        view
        virtual
        returns (FeeDistribution memory);

    function _transfer(
        PoolVintageToken memory vintage,
        address from,
        address to,
        uint256 amount
    ) internal virtual;

    function _retire(
        PoolVintageToken memory vintage,
        address from,
        uint256 amount
    ) internal virtual returns (uint256);

    function _checkEligible(PoolVintageToken memory vintage)
        internal
        view
        virtual;

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

    /// @notice Update the fee redeem burn percentage
    /// @param feeRedeemBurnPercentageInBase_ percentage of fee in base
    function setFeeRedeemBurnPercentage(uint256 feeRedeemBurnPercentageInBase_)
        external
        virtual
    {
        onlyPoolOwner();
        require(
            feeRedeemBurnPercentageInBase_ < feeRedeemDivider,
            Errors.CP_INVALID_FEE
        );
        _feeRedeemBurnPercentageInBase = feeRedeemBurnPercentageInBase_;
        emit RedeemBurnFeeUpdated(feeRedeemBurnPercentageInBase_);
    }

    /// @notice Update the fee redeem burn address
    /// @param feeRedeemBurnAddress_ address to transfer the fees to burn
    function setFeeRedeemBurnAddress(address feeRedeemBurnAddress_)
        external
        virtual
    {
        onlyPoolOwner();
        require(feeRedeemBurnAddress_ != address(0), Errors.CP_EMPTY_ADDRESS);
        _feeRedeemBurnAddress = feeRedeemBurnAddress_;
        emit RedeemFeeBurnAddressUpdated(feeRedeemBurnAddress_);
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

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    function _deposit(
        PoolVintageToken memory vintage,
        uint256 amount,
        uint256 maxFee
    ) internal returns (uint256 mintedPoolTokenAmount) {
        onlyUnpaused();

        // Ensure the vintage token is eligible to be deposited
        _checkEligible(vintage);

        // Ensure there is space in the pool
        uint256 remainingSpace = getRemaining();
        //slither-disable-next-line incorrect-equality
        if (remainingSpace == 0) {
            revert(Errors.CP_FULL_POOL);
        }

        // If the amount to be deposited exceeds the remaining space, deposit
        // the maximum amount possible up to the cap instead of failing.
        if (amount > remainingSpace) amount = remainingSpace;

        uint256 depositedAmount = amount;
        if (feeCalculator != IFeeCalculator(address(0))) {
            // If a fee module is configured, use it to calculate the minting fees
            FeeDistribution memory feeDistribution = _feeDistribution(
                vintage,
                depositedAmount
            );
            uint256 feeDistributionTotal = getFeeDistributionTotal(
                feeDistribution
            );
            _checkMaxFee(maxFee, feeDistributionTotal);
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

        // Update supply-related storage variables in the pool
        _increaseSupply(vintage, int256(amount));

        // Transfer the TCO2 to the pool
        _transfer(vintage, msg.sender, address(this), amount);

        emit Deposited(vintage.vintageToken, amount);

        return depositedAmount;
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

    /// @dev Internal function to calculate redemption fees.
    /// Made virtual so that each child contract can implement its own
    /// internal fee calculation logic that can be shared with the
    /// current Pool contract. Child contracts will most likely need
    /// to simply expose a public function that returns just the
    /// feeDistributionTotal which is the value that is useful to
    /// external clients who only care about the total fee amount and
    /// not how the fee is going to be distributed.
    function _calculateRedemptionInFees(
        PoolVintageToken[] memory vintages,
        uint256[] memory amounts,
        bool toRetire
    )
        internal
        view
        virtual
        returns (
            uint256[] memory feeAmounts,
            FeeDistribution memory feeDistribution
        );

    /// @dev Internal function to calculate redemption fees.
    /// Made virtual so that each child contract can implement its own
    /// internal fee calculation logic that can be shared with the
    /// current Pool contract. Child contracts will most likely need
    /// to simply expose a public function that returns just the
    /// feeDistributionTotal which is the value that is useful to
    /// external clients who only care about the total fee amount and
    /// not how the fee is going to be distributed.
    function _calculateRedemptionOutFees(
        PoolVintageToken[] memory vintages,
        uint256[] memory amounts,
        bool toRetire
    )
        internal
        view
        virtual
        returns (
            uint256 feeDistributionTotal,
            FeeDistribution memory feeDistribution
        );

    function getFeeDistributionTotal(FeeDistribution memory feeDistribution)
        internal
        pure
        returns (uint256 feeAmount)
    {
        uint256 recipientLen = feeDistribution.recipients.length;
        _checkLength(recipientLen, feeDistribution.shares.length);

        for (uint256 i = 0; i < recipientLen; ++i) {
            feeAmount += feeDistribution.shares[i];
        }
        return feeAmount;
    }

    function _redeemInMany(
        PoolVintageToken[] memory vintages,
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
        uint256 vintageLength = vintages.length;
        _checkLength(vintageLength, amounts.length);
        require(
            feeCalculator == IFeeCalculator(address(0)),
            Errors.CP_NOT_SUPPORTED
        );

        // Initialize return arrays
        redeemedAmounts = new uint256[](vintageLength);
        if (toRetire) {
            retirementIds = new uint256[](vintageLength);
        }

        // Calculate the fees to be paid for the vintage token redemptions
        (
            uint256[] memory feeAmounts,
            FeeDistribution memory feeDistribution
        ) = _calculateRedemptionInFees(vintages, amounts, toRetire);

        // Execute redemptions
        uint256 totalFee = 0;
        for (uint256 i = 0; i < vintageLength; ++i) {
            _checkEligible(vintages[i]);

            uint256 amountToRedeem = amounts[i];
            amountToRedeem -= feeAmounts[i];
            totalFee += feeAmounts[i];

            // Redeem the amount minus the fee
            _redeemSingle(vintages[i], amountToRedeem);

            // If requested, retire the vintage tokens in one go. Callers should
            // first approve the pool in order for the pool to retire
            // on behalf of them
            if (toRetire) {
                retirementIds[i] = _retire(
                    vintages[i],
                    msg.sender,
                    amountToRedeem
                );
            }

            // Keep track of redeemed amounts in return arguments
            // to make the function composable.
            redeemedAmounts[i] = amountToRedeem;
        }

        _checkMaxFee(maxFee, totalFee);

        // Distribute the fee between the recipients
        if (totalFee > 0) {
            distributeRedemptionFee(
                feeDistribution.recipients,
                feeDistribution.shares
            );
        }
    }

    function _checkMaxFee(uint256 maxFee, uint256 amount) internal pure {
        if (maxFee != 0) {
            // Protect caller against getting charged a higher fee than expected
            require(amount <= maxFee, Errors.CP_FEE_TOO_HIGH);
        }
    }

    function _redeemOutMany(
        PoolVintageToken[] memory vintages,
        uint256[] memory amounts,
        uint256 maxFee,
        bool toRetire
    )
        internal
        returns (uint256[] memory retirementIds, uint256 poolAmountSpent)
    {
        onlyUnpaused();
        uint256 vintageLength = vintages.length;
        _checkLength(vintageLength, amounts.length);

        // Initialize return arrays
        if (toRetire) {
            retirementIds = new uint256[](vintageLength);
        }

        // Calculate the fee to be paid for the vintage token redemptions
        (
            uint256 feeDistributionTotal,
            FeeDistribution memory feeDistribution
        ) = _calculateRedemptionOutFees(vintages, amounts, toRetire);
        _checkMaxFee(maxFee, feeDistributionTotal);
        poolAmountSpent += feeDistributionTotal;

        // Distribute the fee between the recipients
        if (feeDistributionTotal != 0) {
            distributeRedemptionFee(
                feeDistribution.recipients,
                feeDistribution.shares
            );
        }

        // Execute redemptions
        for (uint256 i = 0; i < vintageLength; ++i) {
            _checkEligible(vintages[i]);

            // Redeem the amount
            uint256 amountToRedeem = amounts[i];
            poolAmountSpent += amountToRedeem;
            _redeemSingle(vintages[i], amountToRedeem);

            // If requested, retire the vintage tokens in one go. Callers should
            // first approve the pool in order for the pool to retire
            // on behalf of them
            if (toRetire) {
                retirementIds[i] = _retire(
                    vintages[i],
                    msg.sender,
                    amountToRedeem
                );
            }
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
    function _redeemSingle(PoolVintageToken memory vintage, uint256 amount)
        internal
        virtual
    {
        // Burn pool tokens
        _burn(msg.sender, amount);

        // Update supply-related storage variables in the pool
        _increaseSupply(vintage, int256(amount) * -1);

        // Transfer vintage token tokens to the caller
        _transfer(vintage, address(this), msg.sender, amount);

        emit Redeemed(msg.sender, vintage.vintageToken, amount);
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

    function _checkLength(uint256 l1, uint256 l2) internal pure {
        if (l1 != l2) {
            revert(Errors.CP_LENGTH_MISMATCH);
        }
    }

    /// @dev Returns the remaining space in pool before hitting the cap
    function getRemaining() public view returns (uint256) {
        return (supplyCap - totalSupply());
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
