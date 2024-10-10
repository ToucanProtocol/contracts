// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {FeeDistribution} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

import {Errors} from '../libraries/Errors.sol';
import {IPoolFilter} from './interfaces/IPoolFilter.sol';
import {Pool} from './Pool.sol';

abstract contract PoolERC1155able is Pool, ERC1155Holder {
    event ERC1155Deposited(
        address erc1155Addr,
        uint256 tokenId,
        uint256 amount
    );
    event ERC1155Redeemed(
        address account,
        address erc1155Addr,
        uint256 tokenId,
        uint256 amount
    );
    event UnderlyingDecimalsUpdated(uint8 decimals);

    /// @notice Set the underlying decimals for ERC-1155 tokens.
    /// @dev The underlying decimals are the number of decimals the ERC-1155
    /// token uses to represent the underlying asset. For example, if the
    /// ERC-1155 token represents a tonne of carbon, then the underlying
    /// decimals would be 0. If it represents a kilogram of carbon, then the
    /// underlying decimals would be 3.
    /// @param underlyingDecimals_ The number of decimals the ERC-1155 token
    /// uses to represent a tonne of carbon.
    function setUnderlyingDecimals(uint8 underlyingDecimals_) external {
        onlyPoolOwner();
        uint8 poolDecimals = decimals();
        // Underlying decimals cannot be higher than pool decimals, otherwise
        // the conversions in _poolTokenAmount and _underlyingAmount will fail.
        // Also if we allow a higher fidelity token to be deposited then the
        // difference in decimals will be unredeemable. In theory we could check
        // that low decimals in such deposits are not used but we don't have any
        // need to do that yet.
        if (underlyingDecimals_ > poolDecimals)
            revert(Errors.UNDERLYING_DECIMALS_TOO_HIGH);
        _underlyingDecimals = underlyingDecimals_;
        emit UnderlyingDecimalsUpdated(underlyingDecimals_);
    }

    /// @notice Function to limit the maximum pool supply
    /// @dev supplyCap is initially set to 0 and must be increased before deposits
    /// @param newCap New pool supply cap
    function setSupplyCap(uint256 newCap) external override {
        onlyPoolOwner();
        // The supply cap must be of valid precision for the underlying token
        uint256 precision = 10**(decimals() - _underlyingDecimals);
        if (newCap % precision != 0) {
            revert(Errors.INVALID_SUPPLY_CAP);
        }
        supplyCap = newCap;
        emit SupplyCapUpdated(newCap);
    }

    /// @notice Underlying decimals for ERC-1155 tokens. 0 decimals means
    /// that the smallest denomination the ERC-1155 token can represent is
    /// a tonne, 3 decimals means a kilogram, etc.
    function underlyingDecimals() external view returns (uint8) {
        return _underlyingDecimals;
    }

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

    /// @notice View function to calculate redemption fees pre-execution,
    /// according to the amounts of pool tokens to be spent.
    /// @param erc1155s Array of ERC1155 contract addresses
    /// @param tokenIds ids of the vintages of each project
    /// @param amounts Array of pool token amounts to spend in order to redeem
    /// underlying tokens.
    /// @dev The indexes of all arrays should be matching 1:1.
    /// @param toRetire No-op, retirements of ERC-1155 tokens are not
    /// supported from within the pool yet and there are no immediate plans
    /// to add support.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionInFees(
        address[] memory erc1155s,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        bool toRetire
    ) external view virtual returns (uint256 feeDistributionTotal);

    /// @notice View function to calculate redemption fees pre-execution,
    /// according to the amounts of underlying tokens to be redeemed.
    /// @param erc1155s Array of ERC1155 contract addresses
    /// @param tokenIds ids of the vintages of each project
    /// @param amounts Array of underlying token amounts to redeem.
    /// @dev The indexes of all arrays should be matching 1:1.
    /// @param toRetire No-op, retirements of ERC-1155 tokens are not
    /// supported from within the pool yet and there are no immediate plans
    /// to add support.
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
    function tokenBalance(address erc1155, uint256 tokenId)
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
        string memory eligibilityError = IPoolFilter(filter)
            .checkERC1155Eligible(
                vintage.tokenAddress,
                vintage.erc1155VintageTokenId
            );
        if (bytes(eligibilityError).length > 0) {
            revert(eligibilityError);
        }
    }

    function _changeSupply(PoolVintageToken memory vintage, int256 delta)
        internal
        override
    {
        super._changeSupply(vintage, _underlyingAmount(delta));
    }

    function _emitDepositedEvent(
        PoolVintageToken memory vintage,
        uint256 amount
    ) internal override {
        emit ERC1155Deposited(
            vintage.tokenAddress,
            vintage.erc1155VintageTokenId,
            _underlyingAmount(amount)
        );
    }

    function _emitRedeemedEvent(PoolVintageToken memory vintage, uint256 amount)
        internal
        override
    {
        emit ERC1155Redeemed(
            msg.sender,
            vintage.tokenAddress,
            vintage.erc1155VintageTokenId,
            _underlyingAmount(amount)
        );
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
            _underlyingAmount(amount),
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

    /// @dev The underlying amount conversions are helpful to execute
    /// so internal logic can be kept simple by always operating on
    /// pool token decimals. For example, underlying token amounts are
    /// converted to pool token amounts internally so pool ops like
    /// charging fees can be performed.
    function _underlyingAmount(uint256 poolTokenAmount)
        internal
        view
        returns (uint256)
    {
        uint8 decimals = decimals();
        decimals -= _underlyingDecimals;
        return poolTokenAmount / (10**decimals);
    }

    function _underlyingAmount(int256 poolTokenAmount)
        internal
        view
        returns (int256)
    {
        uint8 decimals = decimals();
        decimals -= _underlyingDecimals;
        // The minimum decimals value that can overflow in the int256
        // conversion below is 78 so not anything to be worried about.
        return poolTokenAmount / int256(10**decimals);
    }

    function _poolTokenAmount(uint256 underlyingAmount)
        internal
        view
        returns (uint256)
    {
        uint8 decimals = decimals();
        decimals -= _underlyingDecimals;
        return underlyingAmount * (10**decimals);
    }

    function _poolTokenAmounts(uint256[] memory amounts)
        internal
        view
        returns (uint256[] memory poolTokenAmounts)
    {
        uint256 length = amounts.length;
        poolTokenAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            poolTokenAmounts[i] = _poolTokenAmount(amounts[i]);
        }
    }
}
