// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earthz
pragma solidity 0.8.14;

/// @dev Separate storage contract to improve upgrade safety
abstract contract ToucanCrosschainMessengerStorageV1 {
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
        /// @notice address of the token in the remote chain
        address tokenAddress;
        /// @notice timer keeps track of when the token pair
        /// was created in order to disallow updates to the
        /// pair after a specific amount of time elapses
        uint256 timer;
    }
    /// @dev nonce is used to serialize requests executed
    /// by the source chain in order to avoid duplicates
    /// from being processed in the remote chain
    uint256 public nonce;
    //slither-disable-next-line constable-states
    bytes32 private DEPRECATED_DOMAIN_SEPARATOR;
    /// @dev requests keeps track of a hash of the request
    /// to the request info in order to avoid duplicates
    /// from being processed in the remote chain
    mapping(bytes32 => BridgeRequest) public requests;
    /// @notice remoteTokens maps a token (address) in the source
    /// chain to the domain id of the remote chain (uint32)
    /// to info about the token in the remote chain (RemoteTokenInformation)
    mapping(address => mapping(uint32 => RemoteTokenInformation))
        public remoteTokens;
}

abstract contract ToucanCrosschainMessengerStorage is
    ToucanCrosschainMessengerStorageV1
{}
