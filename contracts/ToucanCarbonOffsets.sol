// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './bases/ToucanCarbonOffsetsDirectRetirements.sol';
import './bases/ToucanCarbonOffsetsWithBatchBase.sol';

/// @notice Implementation contract of the TCO2 tokens (ERC20)
/// These tokenized carbon offsets are specific to a vintage and its associated attributes
/// In order to mint TCO2s a user must deposit a matching CarbonOffsetBatch
/// @dev Each TCO2 contract is deployed via a Beacon Proxy in `ToucanCarbonOffsetsFactory`
contract ToucanCarbonOffsets is
    ToucanCarbonOffsetsWithBatchBase,
    ToucanCarbonOffsetsDirectRetirements
{
    // ----------------------------------------
    //      Constants
    // ----------------------------------------

    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.6.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    // ----------------------------------------
    //       Upgradable related functions
    // ----------------------------------------

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 projectVintageTokenId_,
        address contractRegistry_
    ) external virtual initializer {
        __ERC20_init_unchained(name_, symbol_);
        _projectVintageTokenId = projectVintageTokenId_;
        contractRegistry = contractRegistry_;
    }

    /// @dev function to achieve backwards compatibility
    /// Converts retired amount to an event that can be attached to an NFT
    function convertAmountToEvent()
        internal
        returns (uint256 retirementEventId)
    {
        uint256 amount = retiredAmount[msg.sender];
        retiredAmount[msg.sender] = 0;

        address certAddr = IToucanContractRegistry(contractRegistry)
            .retirementCertificatesAddress();
        retirementEventId = IRetirementCertificates(certAddr).registerEvent(
            msg.sender,
            _projectVintageTokenId,
            amount,
            true
        );
    }

    /// @notice Mint an NFT showing how many tonnes of CO2 have been retired/cancelled
    /// Going forward users should mint NFT directly in the RetirementCertificates contract.
    /// @param retiringEntityString An identifiable string for the retiring entity, eg. their name.
    /// @param beneficiary The beneficiary to set in the NFT.
    /// @param beneficiaryString The beneficiaryString to set in the NFT.
    /// @param retirementMessage The retirementMessage to set in the NFT.
    function mintCertificateLegacy(
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage
    ) external whenNotPaused {
        uint256 retirementEventId = convertAmountToEvent();
        uint256[] memory retirementEventIds = new uint256[](1);
        retirementEventIds[0] = retirementEventId;

        address certAddr = IToucanContractRegistry(contractRegistry)
            .retirementCertificatesAddress();
        //slither-disable-next-line unused-return
        IRetirementCertificates(certAddr).mintCertificate(
            msg.sender,
            retiringEntityString,
            beneficiary,
            beneficiaryString,
            retirementMessage,
            retirementEventIds
        );
    }

    function standardRegistry() public pure override returns (string memory) {
        return 'verra';
    }

    function standardRegistryDecimals() public pure override returns (uint8) {
        return 18;
    }
}
