// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {Router} from '@hyperlane-xyz/core/contracts/client/Router.sol';
import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ToucanCrosschainMessengerStorage.sol';
import './interfaces/IBridgeableToken.sol';
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
    string public constant VERSION = '2.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    /// @notice duration allowing for updates in token pairs post-creation
    uint256 public constant TIMER = 1209600; // 14 Days
    /// @dev EIP712Domain hash used in generating request hashes
    bytes32 public constant EIP712DomainHash =
        keccak256('EIP712Domain(string name,string version,uint256 chainId)');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

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
    event TokenPairRemoved(
        address indexed homeTokenAddress,
        address indexed remoteTokenAddress,
        uint32 domainId
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _mailbox) Router(_mailbox) {
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
        address _owner,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external virtual initializer {
        require(accounts.length == roles.length, 'Array length mismatch');

        _MailboxClient_initialize(address(0), address(0), _owner);
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
    /// @param _homeTokens token addresses on home chain
    /// @param _remoteTokens token addresses on remote chain
    /// @param _domain domain ID of the remote chain whose tokens are being mapped
    function batchAddTokenPair(
        address[] calldata _homeTokens,
        address[] calldata _remoteTokens,
        uint32 _domain
    ) external onlyOwner {
        uint256 homeTokensLen = _homeTokens.length;
        require(homeTokensLen == _remoteTokens.length, 'Array length mismatch');
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < homeTokensLen; ++i) {
            _addTokenPair(_homeTokens[i], _remoteTokens[i], _domain);
        }
    }

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
        _addTokenPair(_homeToken, _remoteToken, _domain);
    }

    function _addTokenPair(
        address _homeToken,
        address _remoteToken,
        uint32 _domain
    ) private {
        require(_homeToken != address(0), '!_homeToken');
        if (remoteTokens_[_homeToken][_domain].timer != 0) {
            require(
                (block.timestamp - remoteTokens_[_homeToken][_domain].timer) <
                    TIMER,
                'timer expired'
            );
        }
        address remoteToken = remoteTokens_[_homeToken][_domain].tokenAddress;
        remoteTokens_[_homeToken][_domain] = RemoteTokenInformation(
            _remoteToken,
            block.timestamp
        );
        if (_remoteToken == address(0)) {
            require(remoteToken != address(0), 'invalid pair removal');
            emit TokenPairRemoved(_homeToken, remoteToken, _domain);
        } else {
            emit TokenPairAdded(_homeToken, _remoteToken, _domain);
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
    /// @param _origin The domain the message is coming from
    /// @param _message The message in the form of raw bytes
    function _handle(
        uint32 _origin,
        bytes32, // _sender, // commented out because parameter not used
        bytes calldata _message
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

    /// @notice Fetch the amount that needs to be used as a fee
    /// in order to to pay for the gas of the transfer on the
    /// destination domain.
    /// @dev Use the result of this function as msg.value when calling
    /// `transferTokens` or `transferTokensToRecipient`.
    /// @param _destinationDomain The domain to send the message to
    /// @param _token address of token to be bridged
    /// @param _amount the amount of tokens to be bridged
    /// @param _recipient the recipient of tokens in the destination domain
    /// @return The required fee for a token transfer
    function quoteTokenTransferFee(
        uint32 _destinationDomain,
        address _token,
        uint256 _amount,
        address _recipient
    ) external view override returns (uint256) {
        bytes memory message = _buildTokenTransferMessage(
            _destinationDomain,
            _token,
            _amount,
            _recipient,
            bytes32(type(uint256).max)
        );
        return _quoteDispatch(_destinationDomain, message);
    }

    function _buildTokenTransferMessage(
        uint32 _destinationDomain,
        address _token,
        uint256 _amount,
        address _recipient,
        bytes32 _requestHash
    ) internal view returns (bytes memory) {
        address remoteToken = remoteTokens_[_token][_destinationDomain]
            .tokenAddress;
        require(remoteToken != address(0), 'remote token not mapped');
        return
            abi.encode(
                MessageTypes.MINT,
                msg.sender,
                _recipient,
                remoteToken,
                _amount,
                _destinationDomain,
                _requestHash
            );
    }

    /// @notice Transfer tokens to a recipient in the destination domain
    /// @param _destinationDomain The domain to send the tokens to
    /// @param _token address of token to be bridged
    /// @param _amount the amount of tokens to be bridged
    /// @param _recipient the recipient of tokens in the destination domain
    function transferTokensToRecipient(
        uint32 _destinationDomain,
        address _token,
        uint256 _amount,
        address _recipient
    ) public payable whenNotPaused {
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
        requests[requestHash] = BridgeRequest(
            false,
            block.timestamp, // timestamp when the bridge request was sent
            BridgeRequestType.SENT,
            MessageTypes.MINT
        );
        // encode a message to send to the remote xApp Router
        bytes memory _outboundMessage = _buildTokenTransferMessage(
            _destinationDomain,
            _token,
            _amount,
            _recipient,
            requestHash
        );
        // Dispatch the message
        _dispatch(_destinationDomain, _outboundMessage);
        // Burn the tokens on this side of the bridge
        IBridgeableToken(_token).bridgeBurn(msg.sender, _amount);
        emit BridgeRequestSent(
            localDomain,
            _destinationDomain,
            msg.sender,
            _recipient,
            _token,
            _amount,
            currentNonce,
            requestHash
        );
    }

    /// @notice Transfer tokens to a recipient in the destination domain.
    /// The recipient of the tokens in the destination domain is the same as
    /// msg.sender in this context.
    /// @param _destinationDomain The domain to send the message to
    /// @param _token address of token to be bridged
    /// @param _amount the amount of tokens to be bridged
    function transferTokens(
        uint32 _destinationDomain,
        address _token,
        uint256 _amount
    ) external payable {
        transferTokensToRecipient(
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

    function remoteTokens(address _token, uint32 _domain)
        external
        view
        virtual
        override
        returns (RemoteTokenInformation memory)
    {
        return remoteTokens_[_token][_domain];
    }
}
