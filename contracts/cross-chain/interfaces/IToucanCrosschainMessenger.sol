// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {RemoteTokenInformation} from '../ToucanCrosschainMessengerStorage.sol';

interface IToucanCrosschainMessenger {
    function sendMessage(
        uint32 destinationDomain,
        address token,
        uint256 amount
    ) external payable;

    function sendMessageWithRecipient(
        uint32 destinationDomain,
        address token,
        uint256 amount,
        address recipient
    ) external payable;

    function remoteTokens(address _token, uint32 _destinationDomain)
        external
        view
        returns (RemoteTokenInformation memory);
}
