// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {FeeDistribution, IFeeCalculator} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

import {PoolERC1155able} from './PoolERC1155able.sol';
import {Errors} from '../libraries/Errors.sol';

/// @notice Pool with fee calculator template contract
/// Any pool that inherits from this contract will be able to
// charge fees both on deposits and redemptions with the use
/// of a fee calculator contract.
abstract contract PoolWithFeeCalculatorERC1155 is PoolERC1155able {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event FeeCalculatorUpdated(address feeCalculator);

    // ------------------------
    // Admin functions
    // ------------------------

    /// @notice Update the address of the fee module contract
    /// @param _feeCalculator Fee module contract address
    function setFeeCalculator(address _feeCalculator) external {
        onlyPoolOwner();
        feeCalculator = IFeeCalculator(_feeCalculator);
        emit FeeCalculatorUpdated(_feeCalculator);
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice View function to calculate deposit fees pre-execution
    /// @dev User specifies in front-end the address and amount they want
    /// @param erc1155 ERC1155 contract address
    /// @param tokenId id representing the vintage
    /// @param amount Amount of ERC-1155 tokens to deposit (0 decimals)
    /// @return feeDistributionTotal Total fee amount to be paid in pool tokens
    function calculateDepositFees(
        address erc1155,
        uint256 tokenId,
        uint256 amount
    ) external view virtual override returns (uint256 feeDistributionTotal) {
        onlyUnpaused();

        // If the fee calculator is not configured, no fees are paid
        if (address(feeCalculator) == address(0)) {
            return 0;
        }

        FeeDistribution memory feeDistribution = feeCalculator
            .calculateDepositFees(
                address(this),
                erc1155,
                tokenId,
                _poolTokenAmount(amount)
            );
        feeDistributionTotal = getFeeDistributionTotal(feeDistribution);
    }

    /// @notice View function to calculate redemption fees pre-execution,
    /// according to the amounts of pool tokens to be spent.
    /// NOTE: This function is not supported yet
    function calculateRedemptionInFees(
        address[] memory,
        uint256[] memory,
        uint256[] memory,
        bool
    ) external view virtual override returns (uint256) {
        revert(Errors.CP_NOT_SUPPORTED);
    }

    function _calculateRedemptionInFees(
        PoolVintageToken[] memory, /* ERC1155 vintages */
        uint256[] memory, /* amounts */
        bool /* toRetire */
    )
        internal
        pure
        override
        returns (
            uint256[] memory, /* feeAmounts */
            FeeDistribution memory /* feeDistribution */
        )
    {
        revert(Errors.CP_NOT_SUPPORTED);
    }

    /// @notice View function to calculate redemption fees pre-execution,
    /// according to the amounts of underlying tokens to be redeemed.
    /// @param erc1155s Array of ERC1155 contract addresses
    /// @param tokenIds ids of the vintages of each project
    /// @param amounts Array of ERC-1155 token amounts to redeem (0 decimals)
    /// The indexes of this array are matching 1:1 with the erc1155s array.
    /// @param toRetire No-op
    /// @return feeDistributionTotal Total fee amount to be paid in pool tokens
    function calculateRedemptionOutFees(
        address[] memory erc1155s,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        bool toRetire
    ) external view virtual override returns (uint256 feeDistributionTotal) {
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(
            erc1155s,
            tokenIds
        );

        (feeDistributionTotal, ) = _calculateRedemptionOutFees(
            vintages,
            _poolTokenAmounts(amounts),
            toRetire
        );
    }

    function _calculateRedemptionOutFees(
        PoolVintageToken[] memory vintages,
        uint256[] memory amountsE18,
        bool toRetire
    )
        internal
        view
        override
        returns (
            uint256 feeDistributionTotal,
            FeeDistribution memory feeDistribution
        )
    {
        onlyUnpaused();
        // Calculating fees for retiring is not supported yet
        require(!toRetire, Errors.CP_NOT_SUPPORTED);
        // Calculating fees for multi-ERC1155 redemptions is not supported yet
        uint256 vintageLength = vintages.length;
        require(vintageLength == 1, Errors.CP_NOT_SUPPORTED);
        _checkLength(vintageLength, amountsE18.length);

        // If the fee calculator is not configured or the caller is exempted, no fees are paid
        if (
            address(feeCalculator) == address(0) ||
            redeemFeeExemptedAddresses[msg.sender]
        ) {
            return (0, FeeDistribution(new address[](0), new uint256[](0)));
        }

        address[] memory erc1155s = new address[](vintageLength);
        uint256[] memory tokenIds = new uint256[](vintageLength);
        for (uint256 i = 0; i < vintageLength; i++) {
            erc1155s[i] = vintages[i].tokenAddress;
            tokenIds[i] = vintages[i].erc1155VintageTokenId;
        }

        feeDistribution = feeCalculator.calculateRedemptionFees(
            address(this),
            erc1155s,
            tokenIds,
            amountsE18
        );
        feeDistributionTotal = getFeeDistributionTotal(feeDistribution);
    }

    /// @notice Deposit function for pool that accepts ERC1155 vintages and mints pool token 1:1
    /// @param erc1155 ERC1155 contract address
    /// @param tokenId id representing the vintage
    /// @param amount Amount of ERC-1155 tokens to be deposited (0 decimals)
    /// @param maxFee Maximum pool token fee to be paid for the deposit. This value cannot be zero.
    /// Use `calculateDepositFees(erc1155,tokenId,amount)` to determine the fee that will be charged
    /// given the state of the pool during this call. Add a buffer on top of the returned
    /// fee amount up to the maximum fee you are willing to pay. (18 decimals)
    /// @dev Eligibility of the ERC1155 token to be deposited is checked via `checkEligible`
    /// @return mintedPoolTokenAmount Amount of pool tokens minted to the caller
    function deposit(
        address erc1155,
        uint256 tokenId,
        uint256 amount,
        uint256 maxFee
    ) external returns (uint256 mintedPoolTokenAmount) {
        if (address(feeCalculator) != address(0)) {
            require(maxFee != 0, Errors.CP_INVALID_MAX_FEE);
        }
        PoolVintageToken memory pvToken = _buildPoolVintageToken(
            erc1155,
            tokenId
        );
        return _deposit(pvToken, _poolTokenAmount(amount), maxFee);
    }

    /// @notice Redeem ERC1155 vintages for pool tokens 1:1 minus fees
    /// The amounts provided are the exact amounts of ERC1155 vintages to be redeemed.
    /// @param erc1155s ERC1155 contract address
    /// @param tokenIds id representing the vintage
    /// @param amounts Array of ERC-1155 token amounts to redeem (0 decimals)
    /// The indexes of this array are matching 1:1 with the erc1155s array.
    /// @param maxFee Maximum pool token fee to be paid for the redemption. This value cannot be zero.
    /// Use `calculateRedemptionOutFees(erc1155,tokenIds,amounts,false)` to determine the fee that will
    /// be charged given the state of the pool during this call. Add a buffer on top of the
    /// returned fee amount up to the maximum fee you are willing to pay. (18 decimals)
    /// @return poolAmountSpent The amount of pool tokens spent by the caller
    function redeemOutMany(
        address[] memory erc1155s,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        uint256 maxFee
    ) external virtual returns (uint256 poolAmountSpent) {
        if (address(feeCalculator) != address(0)) {
            require(maxFee != 0, Errors.CP_INVALID_MAX_FEE);
        }
        require(erc1155s.length == 1, Errors.CP_NOT_SUPPORTED);
        PoolVintageToken[] memory vintages = _buildPoolVintageTokens(
            erc1155s,
            tokenIds
        );

        (, poolAmountSpent) = _redeemOutMany(
            vintages,
            _poolTokenAmounts(amounts),
            maxFee,
            false
        );
    }
}
