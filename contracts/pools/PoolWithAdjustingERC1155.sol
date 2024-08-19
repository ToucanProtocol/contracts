// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Errors} from '../libraries/Errors.sol';
import {PoolWithFeeCalculatorERC1155} from './PoolWithFeeCalculatorERC1155.sol';

/// @notice Apply adjustments to the minting and burning of pool tokens.
/// Any pool for ERC-1155 tokens that inherits from this contract will be
/// able to control the amounts being minted and burned based on the scores
/// set for the ERC-1155 tokens.
abstract contract PoolWithAdjustingERC1155 is PoolWithFeeCalculatorERC1155 {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event ScoreUpdated(address erc1155, uint256 tokenId, uint256 score);

    // ------------------------
    // Admin functions
    // ------------------------

    /// @notice Set scores for ERC-1155 vintage tokens. Scores range from 0 to
    /// 100 and determine the percentage of pool tokens minted or burnt during
    /// deposits or redemptions. A score of 0 disables depositing and redeeming
    /// for the vintage token.
    /// @dev Only executable by the pool owner
    /// @param erc1155s Array of ERC-1155 contracts
    /// @param tokenIds Array of ERC-1155 token IDs
    /// @param newScores Array of scores to set
    function setScores(
        address[] calldata erc1155s,
        uint256[] calldata tokenIds,
        uint256[] calldata newScores
    ) external {
        onlyPoolOwner();

        uint256 erc1155sLength = erc1155s.length;
        _checkLength(erc1155sLength, tokenIds.length);
        _checkLength(erc1155sLength, newScores.length);

        for (uint256 i = 0; i < erc1155sLength; ++i) {
            address erc1155 = erc1155s[i];
            uint256 tokenId = tokenIds[i];
            uint256 score = newScores[i];

            // Currently the smart contract does not provide logic to handle
            // score updates for already deposited tokens. This is problematic
            // because if the score of a deposited token is decreased, then it's
            // possible for redemptions to fail because there will not be enough
            // pool tokens held by the pool to burn. Until we implement this
            // missing logic, we disable score updates for already deposited
            // tokens altogether.
            require(
                _vintageDeposited[erc1155][tokenId] == false,
                'vintage already deposited'
            );

            require(erc1155 != address(0), Errors.CP_EMPTY_ADDRESS);
            require(score <= 100, Errors.INVALID_ERC1155_SCORE);

            _scores[erc1155][tokenId] = score;

            emit ScoreUpdated(erc1155, tokenId, score);
        }
    }

    // ----------------------------
    //   Permissionless functions
    // ----------------------------

    /// @notice Get the score for an ERC-1155 vintage token. Scores range from
    /// 0 to 100 and determine the percentage of pool tokens minted or burnt
    /// during deposits or redemptions. A score of 0 means that the vintage
    /// token cannot be deposited or redeemed.
    /// @param erc1155 Address of the ERC-1155 contract
    /// @param tokenId ID of the ERC-1155 token
    /// @return score The score of the ERC-1155 token
    function scores(address erc1155, uint256 tokenId)
        external
        view
        returns (uint256 score)
    {
        return _scores[erc1155][tokenId];
    }

    /// @notice Calculate the adjusted amount of pool tokens to mint
    /// for a deposit of the provided amount of the ERC-1155 token.
    /// @param erc1155 Address of the ERC-1155 contract
    /// @param tokenId ID of the ERC-1155 token
    /// @param amount Amount of ERC-1155 tokens to deposit
    /// @return adjustedAmount The amount of pool tokens minted to the user
    function calculateDepositAdjustedAmount(
        address erc1155,
        uint256 tokenId,
        uint256 amount
    ) external view returns (uint256 adjustedAmount) {
        onlyUnpaused();

        adjustedAmount = _calculateDepositAdjustedAmount(
            _buildPoolVintageToken(erc1155, tokenId),
            _poolTokenAmount(amount)
        );
    }

    /// @notice Calculate the amounts of pool tokens needed in order to
    /// redeem the provided amount of the ERC-1155 token.
    /// @param erc1155 Address of the ERC-1155 contract
    /// @param tokenId ID of the ERC-1155 token
    /// @param amount Amount of ERC-1155 token to redeem
    /// @return adjustedAmount The amount of pool tokens to be burnt
    /// by the caller
    function calculateRedeemOutAdjustedAmount(
        address erc1155,
        uint256 tokenId,
        uint256 amount
    ) external view returns (uint256 adjustedAmount) {
        onlyUnpaused();

        adjustedAmount = _calculateRedeemOutAdjustedAmount(
            _buildPoolVintageToken(erc1155, tokenId),
            _poolTokenAmount(amount)
        );
    }

    /// @notice Mint pool tokens based on the amount and score of the
    /// ERC-1155 token.
    /// @dev caller gets minted an adjusted amount, based on the
    /// score of the token, and the rest gets minted to the pool.
    /// @param account Address of the user to mint tokens to
    /// @param amount Amount of pool tokens to mint to the user. Adjustments
    /// will be made by this function based on the score of the vintage.
    /// @param feeDistributionTotal Fee in pool tokens paid by the user
    /// @param vintage ERC-1155 token vintage to be deposited
    /// @return callerMintedAmount The amount of pool tokens minted
    /// to the caller
    function _mint(
        address account,
        uint256 amount,
        uint256 feeDistributionTotal,
        PoolVintageToken memory vintage
    ) internal override returns (uint256 callerMintedAmount) {
        _vintageDeposited[vintage.tokenAddress][
            vintage.erc1155VintageTokenId
        ] = true;

        // The adjusted amount should be calculated based on the total minted pool tokens
        uint256 totalAmount = amount + feeDistributionTotal;
        uint256 adjustedAmount = _calculateDepositAdjustedAmount(
            vintage,
            totalAmount
        );
        callerMintedAmount = adjustedAmount - feeDistributionTotal;

        // mint adjusted amount to the user
        _mint(account, callerMintedAmount);

        // mint the remaining amount to the pool if an adjustment was made
        if (adjustedAmount < totalAmount)
            _mint(address(this), totalAmount - adjustedAmount);
    }

    /// @notice Burn pool tokens based on the amount and score of the
    /// ERC-1155 token.
    /// @dev caller burns an adjusted amount, based on the
    /// score of the token, and the rest gets burnt from the pool
    /// @param account Address of the user to burn tokens from
    /// @param amountE18 Amount of pool tokens to burn from the caller.
    /// Adjustments will be made by this function based on the score
    /// of the vintage.
    /// @param vintage ERC-1155 token vintage to be redeemed
    /// @return burntAmount The amount of pool tokens burnt by the caller
    function _burn(
        address account,
        uint256 amountE18,
        PoolVintageToken memory vintage
    ) internal override returns (uint256 burntAmount) {
        burntAmount = _calculateRedeemOutAdjustedAmount(vintage, amountE18);

        // burn the amount from user
        _burn(account, burntAmount);

        // burn the remaining amount using excess tokens from the pool
        if (amountE18 > burntAmount)
            _burn(address(this), amountE18 - burntAmount);
    }

    /// @notice Calculate the adjusted amount of pool tokens to mint
    /// for a deposit of the provided amount of the ERC-1155 token.
    /// @param vintage ERC-1155 token vintage to be deposited
    /// @param amountE18 Amount of ERC-1155 tokens to deposit, adjusted to
    /// 18 decimals
    /// @return The amount of pool tokens to be minted to the user
    function _calculateDepositAdjustedAmount(
        PoolVintageToken memory vintage,
        uint256 amountE18
    ) internal view returns (uint256) {
        uint256 score = _scores[vintage.tokenAddress][
            vintage.erc1155VintageTokenId
        ];
        require(score != 0, Errors.EMPTY_ERC155_SCORE);

        return (amountE18 * score) / 100;
    }

    /// @notice Calculate the amount of pool tokens to burn
    /// for a redemption of the provided amount of the ERC-1155 token.
    /// @param vintage ERC-1155 token vintage to be redeemed
    /// @param amountE18 Amount of ERC-1155 token to redeem, adjusted to 18 decimals
    /// @return The amount of pool tokens to be burnt
    function _calculateRedeemOutAdjustedAmount(
        PoolVintageToken memory vintage,
        uint256 amountE18
    ) internal view returns (uint256) {
        uint256 score = _scores[vintage.tokenAddress][
            vintage.erc1155VintageTokenId
        ];
        require(score != 0, Errors.EMPTY_ERC155_SCORE);

        return (amountE18 * score) / 100;
    }
}
