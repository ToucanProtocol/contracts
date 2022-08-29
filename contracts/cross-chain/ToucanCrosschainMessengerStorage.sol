// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earthz
pragma solidity >=0.8.4 <=0.8.14;

/// @dev Separate storage contract to improve upgrade safety
contract ToucanCrosschainMessengerStorage {
    enum BridgeRequestType {
        NOT_REGISTERED, // 0
        SENT, // 1
        RECEIVED // 2
    }

    enum MessageTypes {
        MINT
    }

    struct BridgeRequest {
        bool isReverted; // this state is added for future addition of revert functionality
        uint256 timestamp;
        BridgeRequestType requestType;
        MessageTypes messageType;
    }
    
    struct RemoteTokenInformation {
        address tokenAddress;
        uint256 timer;
    }
    uint256 public nonce;
    bytes32 public DOMAIN_SEPARATOR;
    mapping(bytes32 => BridgeRequest) public requests;
    mapping(address => mapping(uint32 => RemoteTokenInformation))
        public remoteTokens;
}
