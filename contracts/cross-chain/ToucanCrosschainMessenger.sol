// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Router} from '@abacus-network/app/contracts/Router.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ToucanCrosschainMessengerStorage.sol';
import './interfaces/IBridgeableToken.sol';

contract ToucanCrosschainMessenger is
    PausableUpgradeable,
    Router,
    UUPSUpgradeable,
    ToucanCrosschainMessengerStorage
{
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    string public constant VERSION = '1.1.0';
    uint256 public constant TIMER = 1209600; // 14 Days
    bytes32 public constant EIP712DomainHash =
        keccak256('EIP712Domain(string name,string version,uint256 chainId)');

    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event BridgeRequestReceived(
        uint32 indexed originDomain,
        uint32 toDomain,
        address indexed bridger,
        address recipient,
        address indexed token,
        uint256 amount,
        bytes32 requesthash
    );
    event BridgeRequestSent(
        uint32 originDomain,
        uint32 indexed toDomain,
        address indexed bridger,
        address recipient,
        address indexed token,
        uint256 amount,
        uint256 nonce,
        bytes32 requesthash
    );

    event TokenPairAdded(
        address indexed homeTokenAddress,
        address indexed remoteTokenAddress,
        uint32 domainId
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(address _abacusConnectionManager)
        external
        virtual
        initializer
    {
        __Router_initialize(_abacusConnectionManager);
        __Pausable_init();
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712DomainHash,
                    'ToucanCrosschainMessenger',
                    VERSION,
                    block.chainid
                )
            );
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    // ----------------------------------------
    //      Admin functions
    // ----------------------------------------

    /// @notice Adds new token pair than can be bridged
    /// @dev Called by owner to add or map home token address to remote token address.
    /// Changing the remote token address can only be done within a 7 day period, after first
    /// setting it.
    /// @param _homeToken token address on home chain
    /// @param _remoteToken token address on remote chain
    /// @param _domain domain ID of the remote chain whose token is being mapped
    function addTokenPair(
        address _homeToken,
        address _remoteToken,
        uint32 _domain
    ) external onlyOwner {
        require(
            _homeToken != address(0) && _remoteToken != address(0),
            '!_homeToken || !_remoteTokens'
        );
        if (remoteTokens[_homeToken][_domain].timer != 0) {
            require(
                (block.timestamp - remoteTokens[_homeToken][_domain].timer) <
                    TIMER,
                'timer expired'
            );
        }
        remoteTokens[_homeToken][_domain] = RemoteTokenInformation(
            _remoteToken,
            block.timestamp
        );
        emit TokenPairAdded(_homeToken, _remoteToken, _domain);
    }

    /// @notice Pauses the cross chain bridge
    /// @dev when invoked by owner it Pauses the cross chain bridging logic to interact with abacus
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpauses the cross chain bridge
    /// @dev when invoked by owner it unpauses the cross chain bridging logic to interact with abacus
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    // ----------------------------------------
    //      Message-handling functions
    // ----------------------------------------

    /// @notice Receive messages sent via Abacus from other remote Routers;
    /// parse the contents of the message and enact the message's effects on the local chain
    /// @dev it is internally invoked via handle() which is invoked by Abacus's inbox
    /// @param _origin The domain the message is coming from
    /// @param _message The message in the form of raw bytes
    function _handle(
        uint32 _origin,
        bytes32, // _sender, // commented out because parameter not used
        bytes memory _message
    ) internal virtual override whenNotPaused {
        // currently only one message type supported, i.e. mint type
        (
            uint8 messageType,
            address bridger,
            address recipient,
            address token,
            uint256 amount,
            uint32 toDomain,
            bytes32 requestHash
        ) = abi.decode(
                _message,
                (uint8, address, address, address, uint256, uint32, bytes32)
            );
        require(
            requests[requestHash].requestType ==
                BridgeRequestType.NOT_REGISTERED,
            'Bridge Request Executed'
        );
        requests[requestHash] = BridgeRequest(
            false,
            block.timestamp, // timestamp when the bridge request was received
            BridgeRequestType.RECEIVED,
            MessageTypes(messageType)
        );
        if (MessageTypes(messageType) == MessageTypes.MINT) {
            IBridgeableToken(token).bridgeMint(recipient, amount);
            emit BridgeRequestReceived(
                _origin,
                toDomain,
                bridger,
                recipient,
                token,
                amount,
                requestHash
            );
        } else {
            revert('Unsupported Operation');
        }
    }

    // ----------------------------------------
    //      Message-dispatching functions
    // ----------------------------------------

    /// @notice Send a message of "Type A" to a remote xApp Router via Abacus;
    /// this message is called to take some action in the cross-chain context
    /// @param _destinationDomain The domain to send the message to
    /// @param _token address of token to be bridged
    /// @param _amount the amount of tokens to be bridged
    /// @param _recipient the recipient of tokens in the destination domain
    function sendMessageWithRecipient(
        uint32 _destinationDomain,
        address _token,
        uint256 _amount,
        address _recipient
    ) public payable whenNotPaused {
        require(
            remoteTokens[_token][_destinationDomain].tokenAddress != address(0),
            'remote token not mapped'
        );
        uint256 currentNonce = nonce;
        unchecked {
            ++currentNonce;
        }
        nonce = currentNonce;
        bytes32 requestHash = _generateRequestHash(
            _recipient,
            _token,
            _amount,
            _destinationDomain,
            currentNonce
        );
        // encode a message to send to the remote xApp Router
        address remoteToken = remoteTokens[_token][_destinationDomain]
            .tokenAddress;
        requests[requestHash] = BridgeRequest(
            false,
            block.timestamp, // timestamp when the bridge request was sent
            BridgeRequestType.SENT,
            MessageTypes.MINT
        );
        bytes memory _outboundMessage = abi.encode(
            MessageTypes.MINT,
            msg.sender,
            _recipient,
            remoteToken,
            _amount,
            _destinationDomain,
            requestHash
        );
        // Dispatch Message
        // Pay Gas for processing message
        // And create a checkpoint so message can be processed
        _dispatchWithGas(_destinationDomain, _outboundMessage, msg.value);
        IBridgeableToken(_token).bridgeBurn(msg.sender, _amount);
        emit BridgeRequestSent(
            _localDomain(),
            _destinationDomain,
            msg.sender,
            _recipient,
            _token,
            _amount,
            currentNonce,
            requestHash
        );
    }

    /// @notice Send a message of "Type A" to a remote xApp Router via Abacus;
    /// this message is called to take some action in the cross-chain context.
    /// The recipient of the tokens in the destination domain is the same as
    /// msg.sender here.
    /// @param _destinationDomain The domain to send the message to
    /// @param _token address of token to be bridged
    /// @param _amount the amount of tokens to be bridged
    function sendMessage(
        uint32 _destinationDomain,
        address _token,
        uint256 _amount
    ) external payable {
        sendMessageWithRecipient(
            _destinationDomain,
            _token,
            _amount,
            msg.sender
        );
    }

    function _generateRequestHash(
        address _receiver,
        address _token,
        uint256 _amount,
        uint32 _destinationDomain,
        uint256 _nonce
    ) internal view returns (bytes32 _requestHash) {
        return
            keccak256(
                abi.encodePacked(
                    DOMAIN_SEPARATOR(),
                    _receiver,
                    _token,
                    _amount,
                    _destinationDomain,
                    _nonce
                )
            );
    }
}
