// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {FeeDistribution} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

import {Pool} from './Pool.sol';
import {IPoolFilter} from '../interfaces/IPoolFilter.sol';
import {Errors} from '../libraries/Errors.sol';

abstract contract PoolERC1155able is Pool, ERC1155Holder {
    /// @notice Return the total supply of the project for the
    /// given ERC1155 token.
    /// @return supply
    function totalPerProjectSupply(address erc1155, uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return totalProjectSupply[_projectTokenId(erc1155, tokenId)];
    }

    /// @notice View function to calculate deposit fees pre-execution
    /// @dev User specifies in front-end the address and amount they want
    /// @param erc1155 ERC1155 contract address
    /// @param tokenId id representing the vintage
    /// @param amount Amount to redeem
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateDepositFees(
        address erc1155,
        uint256 tokenId,
        uint256 amount
    ) external view virtual returns (uint256 feeDistributionTotal);

    /// @notice View function to calculate redemption fees pre-execution
    /// @param erc1155s Array of ERC1155 contract addresses
    /// @param tokenIds ids of the vintages of each project
    /// @param amounts Array of pool token amounts to spend in order to redeem TCO2s.
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionInFees(
        address[] memory erc1155s,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        bool toRetire
    ) external view virtual returns (uint256 feeDistributionTotal);

    /// @notice View function to calculate redemption fees pre-execution
    /// @param erc1155s Array of ERC1155 contract addresses
    /// @param tokenIds ids of the vintages of each project
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionOutFees(
        address[] memory erc1155s,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        bool toRetire
    ) external view virtual returns (uint256 feeDistributionTotal);

    /// @notice Returns the balance of the carbon offset found in the pool
    /// @param erc1155 ERC1155 contract address
    /// @param tokenId id representing the vintage
    /// @return balance pool balance
    function tokenBalances(address erc1155, uint256 tokenId)
        public
        view
        returns (uint256 balance)
    {
        return IERC1155(erc1155).balanceOf(address(this), tokenId);
    }

    /// @notice Checks if token to be deposited is eligible for this pool.
    /// Reverts if not.
    /// Beware that the revert reason might depend on the underlying implementation
    /// of IPoolFilter.checkEligible
    /// @param erc1155 the ERC1155 contract to check
    /// @param tokenId the token id
    /// @return isEligible true if address is eligible and no other issues occur
    function checkEligible(address erc1155, uint256 tokenId)
        external
        view
        virtual
        returns (bool isEligible)
    {
        _checkEligible(_buildPoolVintageToken(erc1155, tokenId));

        return true;
    }

    // Overrides

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Receiver, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Internal

    function _checkEligible(PoolVintageToken memory vintage)
        internal
        view
        override
    {
        //slither-disable-next-line unused-return
        try
            IPoolFilter(filter).checkERC1155Eligible(
                vintage.tokenAddress,
                vintage.erc1155VintageTokenId
            )
        returns (
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
            revert(string.concat('unexpected error: ', string(reason)));
        }
    }

    function _buildPoolVintageTokens(
        address[] memory erc1155s,
        uint256[] memory tokenIds
    ) internal view returns (PoolVintageToken[] memory vintageTokens) {
        uint256 length = erc1155s.length;
        vintageTokens = new PoolVintageToken[](length);
        for (uint256 i = 0; i < length; i++) {
            vintageTokens[i] = _buildPoolVintageToken(erc1155s[i], tokenIds[i]);
        }
    }

    function _buildPoolVintageToken(address erc1155, uint256 tokenId)
        internal
        view
        returns (PoolVintageToken memory)
    {
        return
            PoolVintageToken(
                erc1155,
                tokenId,
                _projectTokenId(erc1155, tokenId)
            );
    }

    function _increaseSupply(PoolVintageToken memory vintage, int256 delta)
        internal
        virtual
        override
    {
        uint256 currentSupply = totalProjectSupply[vintage.projectTokenId];
        totalProjectSupply[vintage.projectTokenId] = uint256(
            int256(currentSupply) + delta
        );
        totalTCO2Supply = uint256(int256(totalTCO2Supply) + delta);
    }

    function _feeDistribution(PoolVintageToken memory vintage, uint256 amount)
        internal
        view
        virtual
        override
        returns (FeeDistribution memory)
    {
        return
            feeCalculator.calculateDepositFees(
                address(this),
                vintage.tokenAddress,
                vintage.erc1155VintageTokenId,
                amount
            );
    }

    function _transfer(
        PoolVintageToken memory vintage,
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        IERC1155(vintage.tokenAddress).safeTransferFrom(
            from,
            to,
            vintage.erc1155VintageTokenId,
            amount,
            ''
        );
    }

    function _retire(
        PoolVintageToken memory vintage,
        address from,
        uint256 amount
    ) internal override returns (uint256) {}

    function _projectTokenId(address erc1155, uint256 tokenId)
        internal
        view
        virtual
        returns (uint256);
}
