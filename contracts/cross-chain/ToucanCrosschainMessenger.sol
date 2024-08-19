// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Router} from '@hyperlane-xyz/core/contracts/client/Router.sol';
import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './ToucanCrosschainMessengerStorage.sol';
import {IBridgeableToken} from './interfaces/IBridgeableToken.sol';
import {IPoolBridgeable} from './interfaces/IPoolBridgeable.sol';
import {IToucanCrosschainMessenger} from './interfaces/IToucanCrosschainMessenger.sol';

contract ToucanCrosschainMessenger is
    IToucanCrosschainMessenger,
    PausableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    Router,
    ToucanCrosschainMessengerStorage
{
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '2.1.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 2;

    /// @dev EIP712Domain hash used in generating request hashes
    bytes32 public constant EIP712DomainHash =
        keccak256('EIP712Domain(string name,string version,uint256 chainId)');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant BRIDGER_ROLE = keccak256('BRIDGER_ROLE');

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
    event PoolRebalancingRequestReceived(
        uint32 indexed originDomain,
        uint32 indexed toDomain,
        address indexed bridger,
        address recipient,
        address[] tokens,
        uint256[] amounts,
        bytes32 requesthash
    );
    event PoolRebalancingRequestSent(
        uint32 indexed originDomain,
        uint32 indexed toDomain,
        address indexed bridger,
        address recipient,
        address[] tokens,
        uint256[] amounts,
        uint256 nonce,
        bytes32 requesthash
    );

    event TokenPairAdded(
        address indexed homeTokenAddress,
        address indexed remoteTokenAddress,
        uint32 domainId
    );
    event TokenPairRemoved(
        address indexed homeTokenAddress,
        address indexed remoteTokenAddress,
        uint32 domainId
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address mailbox) Router(mailbox) {
        _disableInitializers();
    }

    modifier onlyPausers() {
        require(hasRole(PAUSER_ROLE, msg.sender), 'Not authorized');
        _;
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    function initialize(
        address owner,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external virtual initializer {
        require(accounts.length == roles.length, 'Array length mismatch');

        _MailboxClient_initialize(address(0), address(0), owner);
        __Pausable_init();
        __UUPSUpgradeable_init_unchained();
        __AccessControl_init_unchained();

        bool hasDefaultAdmin = false;
        for (uint256 i = 0; i < accounts.length; ++i) {
            _grantRole(roles[i], accounts[i]);
            if (roles[i] == DEFAULT_ADMIN_ROLE) hasDefaultAdmin = true;
        }
        require(hasDefaultAdmin, 'No admin specified');
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

    /// @notice Adds a new set of token pairs than can be bridged
    /// @dev Called by owner to add or map home token addresses to remote token addresses.
    /// @param homeTokens token addresses on home chain
    /// @param remoteTokens_ token addresses on remote chain
    /// @param domain domain ID of the remote chain whose tokens are being mapped
    function batchAddTokenPair(
        address[] calldata homeTokens,
        address[] calldata remoteTokens_,
        uint32 domain
    ) external onlyOwner {
        uint256 homeTokensLen = homeTokens.length;
        require(homeTokensLen == remoteTokens_.length, 'Array length mismatch');
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < homeTokensLen; ++i) {
            _addTokenPair(homeTokens[i], remoteTokens_[i], domain);
        }
    }

    /// @notice Adds new token pair than can be bridged
    /// @dev Called by owner to add or map home token address to remote token address.
    /// Changing the remote token address can only be done within a 7 day period, after first
    /// setting it.
    /// @param homeToken token address on home chain
    /// @param remoteToken token address on remote chain
    /// @param domain domain ID of the remote chain whose token is being mapped
    function addTokenPair(
        address homeToken,
        address remoteToken,
        uint32 domain
    ) external onlyOwner {
        _addTokenPair(homeToken, remoteToken, domain);
    }

    function _addTokenPair(
        address homeToken,
        address remoteToken,
        uint32 domain
    ) private {
        require(homeToken != address(0), '!homeToken');
        address remoteToken_ = _remoteTokens[homeToken][domain].tokenAddress;
        _remoteTokens[homeToken][domain] = RemoteTokenInformation(
            remoteToken,
            block.timestamp
        );
        if (remoteToken == address(0)) {
            require(remoteToken_ != address(0), 'invalid pair removal');
            emit TokenPairRemoved(homeToken, remoteToken_, domain);
        } else {
            emit TokenPairAdded(homeToken, remoteToken, domain);
        }
    }

    /// @notice Pauses the cross chain bridge
    /// @dev when invoked by owner it Pauses the cross chain bridging logic to interact with abacus
    function pause() external onlyPausers whenNotPaused {
        _pause();
    }

    /// @notice Unpauses the cross chain bridge
    /// @dev when invoked by owner it unpauses the cross chain bridging logic to interact with abacus
    function unpause() external onlyPausers whenPaused {
        _unpause();
    }

    // ----------------------------------------
    //      Message-handling functions
    // ----------------------------------------

    /// @notice Receive messages sent via Abacus from other remote Routers;
    /// parse the contents of the message and enact the message's effects on the local chain
    /// @dev it is internally invoked via handle() which is invoked by Abacus's inbox
    /// @param origin The domain the message is coming from
    /// @param message The message in the form of raw bytes
    function _handle(
        uint32 origin,
        bytes32, // sender, // commented out because parameter not used
        bytes calldata message
    ) internal virtual override whenNotPaused {
        uint8 messageTypeInt = abi.decode(message, (uint8));

        if (messageTypeInt == uint8(MessageType.TOKEN_TRANSFER)) {
            _handleTokenTransferRequest(origin, message);
        } else if (messageTypeInt == uint8(MessageType.TCO2_REBALANCE)) {
            _handleTCO2RebalanceRequest(origin, message);
        } else {
            revert('Unsupported Operation');
        }
    }

    function _handleTokenTransferRequest(uint32 origin, bytes memory message)
        internal
    {
        (
            uint8 messageType,
            address bridger,
            address recipient,
            address token,
            uint256 amount,
            uint32 toDomain,
            bytes32 requestHash
        ) = abi.decode(
                message,
                (uint8, address, address, address, uint256, uint32, bytes32)
            );

        _saveIncomingRequest(requestHash, MessageType(messageType));

        IBridgeableToken(token).bridgeMint(recipient, amount);

        emit BridgeRequestReceived(
            origin,
            toDomain,
            bridger,
            recipient,
            token,
            amount,
            requestHash
        );
    }

    function _handleTCO2RebalanceRequest(uint32 origin, bytes memory message)
        internal
    {
        (
            uint8 messageType,
            address bridger,
            address recipient,
            address[] memory tokens,
            uint256[] memory amounts,
            uint32 toDomain,
            bytes32 requestHash
        ) = abi.decode(
                message,
                (uint8, address, address, address[], uint256[], uint32, bytes32)
            );

        _saveIncomingRequest(requestHash, MessageType(messageType));

        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            IBridgeableToken bridgeableToken = IBridgeableToken(token);
            bridgeableToken.bridgeMint(address(this), amount);
            require(
                bridgeableToken.approve(recipient, amount),
                'approval unsuccessful'
            );
        }

        IPoolBridgeable(recipient).completeTCO2Bridging(tokens, amounts);

        emit PoolRebalancingRequestReceived(
            origin,
            toDomain,
            bridger,
            recipient,
            tokens,
            amounts,
            requestHash
        );
    }

    // ----------------------------------------
    //      Message-dispatching functions
    // ----------------------------------------

    /// @notice Fetch the amount that needs to be used as a fee
    /// in order to to pay for the gas of the transfer on the
    /// destination domain.
    /// @dev Use the result of this function as msg.value when calling
    /// `transferTokens` or `transferTokensToRecipient`.
    /// @param destinationDomain The domain to send the message to
    /// @param tokens address of token to be bridged
    /// @param amounts the amount of tokens to be bridged
    /// @param recipient the recipient of tokens in the destination domain
    /// @return The required fee for a token transfer
    function quoteBridgeTCO2sFee(
        uint32 destinationDomain,
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) external view override returns (uint256) {
        bytes memory message = _buildTCO2RebalanceMessage(
            destinationDomain,
            recipient,
            tokens,
            amounts,
            bytes32(type(uint256).max)
        );
        return _quoteDispatch(destinationDomain, message);
    }

    /// @notice Fetch the amount that needs to be used as a fee
    /// in order to to pay for the gas of the transfer on the
    /// destination domain.
    /// @dev Use the result of this function as msg.value when calling
    /// `transferTokens` or `transferTokensToRecipient`.
    /// @param destinationDomain The domain to send the message to
    /// @param token address of token to be bridged
    /// @param amount the amount of tokens to be bridged
    /// @param recipient the recipient of tokens in the destination domain
    /// @return The required fee for a token transfer
    function quoteTokenTransferFee(
        uint32 destinationDomain,
        address token,
        uint256 amount,
        address recipient
    ) external view override returns (uint256) {
        bytes memory message = _buildTokenTransferMessage(
            destinationDomain,
            token,
            amount,
            recipient,
            bytes32(type(uint256).max)
        );
        return _quoteDispatch(destinationDomain, message);
    }

    function _buildTokenTransferMessage(
        uint32 destinationDomain,
        address token,
        uint256 amount,
        address recipient,
        bytes32 requestHash
    ) internal view returns (bytes memory) {
        address remoteToken = _remoteTokens[token][destinationDomain]
            .tokenAddress;
        require(remoteToken != address(0), 'remote token not mapped');
        return
            abi.encode(
                MessageType.TOKEN_TRANSFER,
                msg.sender,
                recipient,
                remoteToken,
                amount,
                destinationDomain,
                requestHash
            );
    }

    /// @notice Transfer tokens to a recipient in the destination domain
    /// @param destinationDomain The domain to send the tokens to
    /// @param token address of token to be bridged
    /// @param amount the amount of tokens to be bridged
    /// @param recipient the recipient of tokens in the destination domain
    function transferTokensToRecipient(
        uint32 destinationDomain,
        address token,
        uint256 amount,
        address recipient
    ) public payable whenNotPaused {
        bytes32 requestHash = _saveOutgoingTokenTransferRequest(
            destinationDomain,
            token,
            recipient,
            amount
        );

        // encode a message to send to the remote xApp Router
        bytes memory _outboundMessage = _buildTokenTransferMessage(
            destinationDomain,
            token,
            amount,
            recipient,
            requestHash
        );
        // Dispatch the message
        _dispatch(destinationDomain, _outboundMessage);
        // Burn the tokens on this side of the bridge
        IBridgeableToken(token).bridgeBurn(msg.sender, amount);
        emit BridgeRequestSent(
            localDomain,
            destinationDomain,
            msg.sender,
            recipient,
            token,
            amount,
            nonce,
            requestHash
        );
    }

    /// @notice Transfer tokens to a recipient in the destination domain.
    /// The recipient of the tokens in the destination domain is the same as
    /// msg.sender in this context.
    /// @param destinationDomain The domain to send the message to
    /// @param token address of token to be bridged
    /// @param amount the amount of tokens to be bridged
    function transferTokens(
        uint32 destinationDomain,
        address token,
        uint256 amount
    ) external payable {
        transferTokensToRecipient(destinationDomain, token, amount, msg.sender);
    }

    /// @notice Bridges multiple tokens to a recipient in the destination domain
    /// @param destinationDomain The domain to send the tokens to
    /// @param tokens addresses of tokens to be bridged
    /// @param amounts the amounts of tokens to be bridged
    /// @param recipient the recipient of tokens in the destination domain
    function bridgeTCO2s(
        uint32 destinationDomain,
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) external payable override whenNotPaused onlyRole(BRIDGER_ROLE) {
        bytes32 requestHash = _saveOutgoingTCO2RebalanceRequest(
            destinationDomain,
            recipient,
            tokens,
            amounts
        );

        bytes memory message = _buildTCO2RebalanceMessage(
            destinationDomain,
            recipient,
            tokens,
            amounts,
            requestHash
        );

        _dispatch(destinationDomain, message);
        emit PoolRebalancingRequestSent(
            localDomain,
            destinationDomain,
            msg.sender,
            recipient,
            tokens,
            amounts,
            nonce,
            requestHash
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            IBridgeableToken(tokens[i]).bridgeBurn(msg.sender, amounts[i]);
        }
    }

    function _buildTCO2RebalanceMessage(
        uint32 destinationDomain,
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes32 requestHash
    ) internal view returns (bytes memory message) {
        uint256 length = tokens.length;
        address[] memory remoteTokens_ = new address[](tokens.length);
        for (uint256 i = 0; i < length; i++) {
            address remoteToken = _remoteTokens[tokens[i]][destinationDomain]
                .tokenAddress;
            require(remoteToken != address(0), 'remote token not mapped');
            require(amounts[i] > 0, 'invalid amount');
            remoteTokens_[i] = remoteToken;
        }

        message = abi.encode(
            MessageType.TCO2_REBALANCE,
            msg.sender,
            recipient,
            remoteTokens_,
            amounts,
            destinationDomain,
            requestHash
        );
    }

    function _saveOutgoingTCO2RebalanceRequest(
        uint32 destinationDomain,
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts
    ) internal returns (bytes32 requestHash) {
        requestHash = _generateRequestHash(
            recipient,
            tokens,
            amounts,
            destinationDomain
        );

        requests[requestHash] = BridgeRequest(
            false,
            block.timestamp,
            BridgeRequestType.SENT,
            MessageType.TCO2_REBALANCE
        );
    }

    function _saveOutgoingTokenTransferRequest(
        uint32 destinationDomain,
        address recipient,
        address token,
        uint256 amount
    ) internal returns (bytes32 requestHash) {
        requestHash = _generateRequestHash(
            recipient,
            token,
            amount,
            destinationDomain
        );
        requests[requestHash] = BridgeRequest(
            false,
            block.timestamp, // timestamp when the bridge request was sent
            BridgeRequestType.SENT,
            MessageType.TOKEN_TRANSFER
        );
    }

    function _saveIncomingRequest(bytes32 requestHash, MessageType messageType)
        internal
    {
        //slither-disable-next-line incorrect-equality
        require(
            requests[requestHash].requestType ==
                BridgeRequestType.NOT_REGISTERED,
            'Bridge Request Executed'
        );

        requests[requestHash] = BridgeRequest(
            false,
            block.timestamp, // timestamp when the bridge request was received
            BridgeRequestType.RECEIVED,
            messageType
        );
    }

    function _generateRequestHash(
        address receiver,
        address token,
        uint256 amount,
        uint32 destinationDomain
    ) internal returns (bytes32 _requestHash) {
        _updateNonce();
        _requestHash = keccak256(
            abi.encodePacked(
                DOMAIN_SEPARATOR(),
                receiver,
                token,
                amount,
                destinationDomain,
                nonce
            )
        );
    }

    function _generateRequestHash(
        address receiver,
        address[] memory tokens,
        uint256[] memory amounts,
        uint32 destinationDomain
    ) internal returns (bytes32 requestHash) {
        uint256 length = tokens.length;
        bytes memory tokensAndAmounts;
        for (uint256 i = 0; i < length; i++) {
            tokensAndAmounts = abi.encodePacked(
                tokensAndAmounts,
                tokens[i],
                amounts[i]
            );
        }

        _updateNonce();
        requestHash = keccak256(
            abi.encodePacked(
                DOMAIN_SEPARATOR(),
                receiver,
                tokensAndAmounts,
                destinationDomain,
                nonce
            )
        );
    }

    function _updateNonce() internal {
        uint256 currentNonce = nonce;
        unchecked {
            ++currentNonce;
        }
        nonce = currentNonce;
    }

    function remoteTokens(address token, uint32 domain)
        external
        view
        virtual
        override
        returns (RemoteTokenInformation memory)
    {
        return _remoteTokens[token][domain];
    }
}
