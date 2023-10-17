// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

import './bases/ToucanCarbonOffsetsWithBatchBaseTypes.sol';
import './interfaces/IToucanCarbonOffsets.sol';
import './interfaces/IToucanCarbonOffsetsEscrow.sol';
import './interfaces/IToucanContractRegistry.sol';
import './ToucanCarbonOffsetsEscrowStorage.sol';

/// @notice Contract for escrowing TCO2s during detokenization
/// or retirement until the off-chain registry confirms the
/// detokenization or retirement request.
contract ToucanCarbonOffsetsEscrow is
    IToucanCarbonOffsetsEscrow,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ToucanCarbonOffsetsEscrowStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.1.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 3;

    /// @dev All roles related to accessing this contract
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    // ----------------------------------------
    //              Events
    // ----------------------------------------

    event ContractRegistryUpdated(address contractRegistry);

    // ----------------------------------------
    //              Modifiers
    // ----------------------------------------

    modifier onlyTCO2() {
        require(
            IToucanContractRegistry(contractRegistry).isValidERC20(msg.sender),
            'Not TCO2'
        );
        _;
    }

    // ----------------------------------------
    //       Upgradable related functions
    // ----------------------------------------

    function initialize(
        address _contractRegistry,
        address[] calldata _accounts,
        bytes32[] calldata _roles
    ) external virtual initializer {
        require(_accounts.length == _roles.length, 'Array length mismatch');

        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __AccessControl_init_unchained();

        bool hasDefaultAdmin = false;
        for (uint256 i = 0; i < _accounts.length; ++i) {
            _grantRole(_roles[i], _accounts[i]);
            if (_roles[i] == DEFAULT_ADMIN_ROLE) hasDefaultAdmin = true;
        }
        require(hasDefaultAdmin, 'No admin specified');
        contractRegistry = _contractRegistry;
        emit ContractRegistryUpdated(_contractRegistry);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    // ----------------------------------------
    //           Admin functions
    // ----------------------------------------

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setToucanContractRegistry(address _address) external onlyOwner {
        contractRegistry = _address;
        emit ContractRegistryUpdated(_address);
    }

    // ----------------------------------------
    //           TCO2 functions
    // ----------------------------------------

    /// @notice Create a new detokenization request.
    /// @dev Only a TCO2 contract can call this function.
    /// Additionally, the escrow contract must have been
    /// approved to transfer the amount of TCO2 to detokenize.
    /// @param user The user that is requesting the detokenization.
    /// @param amount The amount of TCO2 to detokenize.
    /// @param batchTokenIds The ids of the batches to detokenize.
    function createDetokenizationRequest(
        address user,
        uint256 amount,
        uint256[] calldata batchTokenIds
    ) external virtual override onlyTCO2 returns (uint256) {
        // Bump request id
        uint256 requestId = detokenizationRequestIdCounter;
        unchecked {
            ++requestId;
        }
        detokenizationRequestIdCounter = requestId;

        // Keep track of the project vintage token id
        uint256 projectVintageTokenId = getProjectVintageTokenId(msg.sender);

        // Store detokenization request data
        _detokenizationRequests[requestId] = DetokenizationRequest(
            user,
            amount,
            RequestStatus.Pending,
            batchTokenIds,
            projectVintageTokenId
        );

        // Transfer TCO2 from user to escrow contract
        IERC20Upgradeable(msg.sender).safeTransferFrom(
            user,
            address(this),
            amount
        );

        return requestId;
    }

    /// @notice Create a new retirement request.
    /// @dev Only a TCO2 contract can call this function.
    /// Additionally, the escrow contract must have been
    /// approved to transfer the amount of TCO2 to retire.
    /// @param user The user that is requesting the retirement.
    /// @param params Retirement request params.
    function createRetirementRequest(
        address user,
        CreateRetirementRequestParams calldata params
    ) external virtual override onlyTCO2 returns (uint256 requestId) {
        // Bump request id
        requestId = retirementRequestIdCounter;
        unchecked {
            ++requestId;
        }
        retirementRequestIdCounter = requestId;

        // Keep track of the project vintage token id
        uint256 projectVintageTokenId = getProjectVintageTokenId(msg.sender);

        // Store retirement request data
        _retirementRequests[requestId] = RetirementRequest(
            user,
            params.amount,
            RequestStatus.Pending,
            params.tokenIds,
            params.retiringEntityString,
            params.beneficiary,
            params.beneficiaryString,
            params.retirementMessage,
            params.beneficiaryLocation,
            params.consumptionCountryCode,
            params.consumptionPeriodStart,
            params.consumptionPeriodEnd,
            projectVintageTokenId
        );

        // Transfer TCO2 from user to escrow contract
        IERC20Upgradeable(msg.sender).safeTransferFrom(
            user,
            address(this),
            params.amount
        );

        return requestId;
    }

    /// @notice Finalize a retirement request by calling
    /// the retire and mint certificate function in respective
    /// TCO2 Batch, which can only be invoked by the escrow
    /// After retiring the amount of TCO2 is burned.
    /// @dev Only the TCO2 contract can call this function.
    /// @param requestId The id of the request to finalize.
    function finalizeRetirementRequest(uint256 requestId)
        external
        virtual
        override
        onlyTCO2
    {
        RetirementRequest storage request = _retirementRequests[requestId];
        require(request.status == RequestStatus.Pending, 'Not pending request');

        request.status = RequestStatus.Finalized;

        CreateRetirementRequestParams
            memory params = CreateRetirementRequestParams({
                tokenIds: request.batchTokenIds,
                amount: request.amount,
                retiringEntityString: request.retiringEntityString,
                beneficiary: request.beneficiary,
                beneficiaryString: request.beneficiaryString,
                retirementMessage: request.retirementMessage,
                beneficiaryLocation: request.beneficiaryLocation,
                consumptionCountryCode: request.consumptionCountryCode,
                consumptionPeriodStart: request.consumptionPeriodStart,
                consumptionPeriodEnd: request.consumptionPeriodEnd
            });
        IToucanCarbonOffsets(msg.sender).retireAndMintCertificateForEntity(
            request.user,
            params
        );
    }

    /// @notice Finalize a detokenization request by burning
    /// its amount of TCO2.
    /// @dev Only the TCO2 contract can call this function.
    /// @param requestId The id of the request to finalize.
    function finalizeDetokenizationRequest(uint256 requestId)
        external
        virtual
        override
        onlyTCO2
    {
        DetokenizationRequest storage request = _detokenizationRequests[
            requestId
        ];
        require(request.status == RequestStatus.Pending, 'Not pending request');

        request.status = RequestStatus.Finalized;

        uint256 amount = request.amount;
        IERC20Upgradeable(msg.sender).safeApprove(address(this), amount);
        IToucanCarbonOffsets(msg.sender).burnFrom(address(this), amount);
    }

    /// @notice Revert a retirement request by transfering amount of TCO2
    /// back to the user.
    /// @dev Only the TCO2 contract can call this function.
    /// @param requestId The id of the request to revert.
    function revertRetirementRequest(uint256 requestId)
        external
        virtual
        override
        onlyTCO2
    {
        RetirementRequest storage request = _retirementRequests[requestId];
        require(request.status == RequestStatus.Pending, 'Not pending request');

        request.status = RequestStatus.Reverted;

        IERC20Upgradeable(msg.sender).safeTransfer(
            request.user,
            request.amount
        );
    }

    /// @notice Revert a detokenization request by transfering amount of TCO2
    /// back to the user.
    /// @dev Only the TCO2 contract can call this function.
    /// @param requestId The id of the request to revert.
    function revertDetokenizationRequest(uint256 requestId)
        external
        virtual
        override
        onlyTCO2
    {
        DetokenizationRequest storage request = _detokenizationRequests[
            requestId
        ];
        require(request.status == RequestStatus.Pending, 'Not pending request');

        request.status = RequestStatus.Reverted;

        IERC20Upgradeable(msg.sender).safeTransfer(
            request.user,
            request.amount
        );
    }

    // ----------------------------------------
    //           Read-only functions
    // ----------------------------------------

    function getProjectVintageTokenId(address tco2)
        internal
        view
        returns (uint256)
    {
        return IToucanCarbonOffsets(tco2).projectVintageTokenId();
    }

    function detokenizationRequests(uint256 requestId)
        external
        view
        virtual
        override
        returns (DetokenizationRequest memory)
    {
        return _detokenizationRequests[requestId];
    }

    function retirementRequests(uint256 requestId)
        external
        view
        virtual
        override
        returns (RetirementRequest memory)
    {
        return _retirementRequests[requestId];
    }
}
