// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import {FeeDistribution} from '@toucanprotocol/dynamic-fee-pools/src/interfaces/IFeeCalculator.sol';

import {VintageData, IToucanCarbonOffsets} from '../interfaces/IToucanCarbonOffsets.sol';
import {Pool} from './Pool.sol';
import {Errors} from '../libraries/Errors.sol';
import {IPoolFilter} from '../interfaces/IPoolFilter.sol';

abstract contract PoolERC20able is Pool {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Return the total supply of the project for the
    /// given TCO2 token.
    /// @return supply
    function totalPerProjectSupply(address tco2)
        external
        view
        returns (uint256)
    {
        return totalProjectSupply[_projectTokenId(tco2)];
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
        _redeemSingle(_buildPoolVintageToken(tco2), amount);
        // User has to approve the pool contract in the TCO2 contract
        // in order for this function to successfully burn the tokens
        IToucanCarbonOffsets(tco2).burnFrom(msg.sender, amount);
    }

    /// @notice View function to calculate deposit fees pre-execution
    /// @dev User specifies in front-end the address and amount they want
    /// @param tco2 TCO2 contract addresses
    /// @param amount Amount to redeem
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateDepositFees(address tco2, uint256 amount)
        external
        view
        virtual
        returns (uint256 feeDistributionTotal);

    /// @notice View function to calculate redemption fees pre-execution
    /// @param tco2s Array of TCO2 contract addresses
    /// @param amounts Array of pool token amounts to spend in order to redeem TCO2s.
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionInFees(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    ) external view virtual returns (uint256 feeDistributionTotal);

    /// @notice View function to calculate redemption fees pre-execution
    /// @param tco2s Array of TCO2 contract addresseså
    /// The indexes of this array are matching 1:1 with the tco2s array.
    /// @param toRetire Whether the TCO2s will be retired atomically
    /// with the redemption. It may be that lower fees will be charged
    /// in this case.
    /// @return feeDistributionTotal Total fee amount to be paid
    function calculateRedemptionOutFees(
        address[] memory tco2s,
        uint256[] memory amounts,
        bool toRetire
    ) external view virtual returns (uint256 feeDistributionTotal);

    /// @notice Returns the balance of the carbon offset found in the pool
    function tokenBalances(address tco2) public view returns (uint256) {
        return IERC20Upgradeable(tco2).balanceOf(address(this));
    }

    /// @notice Checks if token to be deposited is eligible for this pool.
    /// Reverts if not.
    /// Beware that the revert reason might depend on the underlying implementation
    /// of IPoolFilter.checkEligible
    /// @param vintageToken the contract to check
    /// @return isEligible true if address is eligible and no other issues occur
    function checkEligible(address vintageToken)
        external
        view
        virtual
        returns (bool isEligible)
    {
        _checkEligible(_buildPoolVintageToken(vintageToken));

        return true;
    }

    // Internal

    function _checkEligible(PoolVintageToken memory vintage)
        internal
        view
        override
    {
        //slither-disable-next-line unused-return
        try IPoolFilter(filter).checkEligible(vintage.tokenAddress) returns (
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

    function _increaseSupply(PoolVintageToken memory vintage, int256 delta)
        internal
        virtual
        override
    {
        totalProjectSupply[vintage.projectTokenId] = uint256(
            int256(totalProjectSupply[vintage.projectTokenId]) + delta
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
                amount
            );
    }

    function _transfer(
        PoolVintageToken memory vintage,
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from == address(this)) {
            IERC20Upgradeable(vintage.tokenAddress).safeTransfer(to, amount);
        } else {
            IERC20Upgradeable(vintage.tokenAddress).safeTransferFrom(
                from,
                to,
                amount
            );
        }
    }

    function _retire(
        PoolVintageToken memory vintage,
        address from,
        uint256 amount
    ) internal override returns (uint256) {
        return
            IToucanCarbonOffsets(vintage.tokenAddress).retireFrom(from, amount);
    }

    function _buildPoolVintageTokens(address[] memory tco2s)
        internal
        view
        returns (PoolVintageToken[] memory vintages)
    {
        uint256 length = tco2s.length;
        vintages = new PoolVintageToken[](length);
        for (uint256 i = 0; i < length; i++) {
            vintages[i] = _buildPoolVintageToken(tco2s[i]);
        }
    }

    function _buildPoolVintageToken(address tco2)
        internal
        view
        returns (PoolVintageToken memory)
    {
        return PoolVintageToken(tco2, 0, _projectTokenId(tco2));
    }

    function _projectTokenId(address tco2) internal view returns (uint256) {
        return IToucanCarbonOffsets(tco2).getVintageData().projectTokenId;
    }
}
