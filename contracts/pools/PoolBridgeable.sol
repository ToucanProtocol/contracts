// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '../cross-chain/interfaces/IToucanCrosschainMessenger.sol';
import '../interfaces/IToucanCarbonOffsets.sol';
import {Errors} from '../libraries/Errors.sol';
import {Pool} from './Pool.sol';

abstract contract PoolBridgeable is Pool {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event RouterUpdated(address router);

    event TCO2RebalanceRequestInitiated(
        uint32 indexed destinationDomain,
        address[] tco2s,
        uint256[] amounts
    );
    event TCO2RebalanceRequestCompleted(address[] tco2s, uint256[] amounts);

    // -------------------------------------
    //   Functions
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
        _checkLength(tco2Length, amounts.length);

        address tcm = router;
        address recipient = _getRemotePoolAddress(tcm, destinationDomain);

        fee = IToucanCrosschainMessenger(tcm).quoteBridgeTCO2sFee(
            destinationDomain,
            tco2s,
            amounts,
            recipient
        );
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
        _checkLength(tco2Length, amounts.length);

        // TODO: Disallow bridging more TCO2s than an amount that
        // would bring the pool to imbalance, ie., end up with more
        // pool tokens than TCO2s in the pool in the source chain.

        // Read the address of the remote pool from ToucanCrosschainMessenger
        // and set that as a recipient in our cross-chain messages.
        address tcm = router;
        address recipient = _getRemotePoolAddress(tcm, destinationDomain);

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
            address tco2 = tco2s[i];
            uint256 amount = amounts[i];

            // Update supply-related storage variables in the pool
            VintageData memory vData = IToucanCarbonOffsets(tco2)
                .getVintageData();
            require(
                totalProjectSupply[vData.projectTokenId] >= amount,
                'insufficient vintage amount'
            );
            totalProjectSupply[vData.projectTokenId] -= amount;
            // this is enforced by an implicit invariant that makes
            // sure a single project supply can never be more than
            // the total underlying supply. Adding a check will
            // anyway make debugging easier should the invariant
            // unexpectedly be broken.
            require(
                totalUnderlyingSupply >= amount,
                'insufficient underlying supply'
            );
            totalUnderlyingSupply -= amount;
        }

        // Transfer tokens to recipient
        //slither-disable-next-line reentrancy-eth
        IToucanCrosschainMessenger(tcm).bridgeTCO2s{value: msg.value}(
            destinationDomain,
            tco2s,
            amounts,
            recipient
        );

        emit TCO2RebalanceRequestInitiated(destinationDomain, tco2s, amounts);
    }

    /// @notice Allows a router to complete the bridging of tokens.
    /// It transfers the tokens to the pool itself and updates the counters.
    /// @param tco2s The TCO2s that have been bridged
    /// @param amounts The amounts of TCO2s that have been bridged
    function completeTCO2Bridging(
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external {
        onlyRouter();
        uint256 tco2Length = tco2s.length;
        require(tco2Length != 0, Errors.CP_EMPTY_ARRAY);
        _checkLength(tco2Length, amounts.length);

        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < tco2Length; ++i) {
            address tco2 = tco2s[i];
            uint256 amount = amounts[i];

            // Update supply-related storage variables in the pool
            VintageData memory vData = IToucanCarbonOffsets(tco2)
                .getVintageData();

            PoolVintageToken memory vintage = PoolVintageToken(
                tco2,
                0,
                vData.projectTokenId
            );

            // Update supply-related storage variables in the pool
            _changeSupply(vintage, int256(amount));

            // Transfer the underlying token to the pool
            _transfer(vintage, msg.sender, address(this), amount);
        }

        emit TCO2RebalanceRequestCompleted(tco2s, amounts);
    }
}
