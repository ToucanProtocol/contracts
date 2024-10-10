// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsBase.sol';

/// @notice Base contract for any TCO2 token that can be retired
/// directly on-chain.
abstract contract ToucanCarbonOffsetsDirectRetirements is
    ToucanCarbonOffsetsBase
{
    // ----------------------------------------
    //              Functions
    // ----------------------------------------

    /// @notice Retirement/Cancellation of TCO2 tokens (the actual offsetting),
    /// which results in the tokens being burnt
    function retire(uint256 amount)
        external
        virtual
        whenNotPaused
        returns (uint256 retirementEventId)
    {
        retirementEventId = _retire(msg.sender, amount, msg.sender);
    }

    /// @dev Allow for pools or third party contracts to retire for the user
    /// Requires approval
    function retireFrom(address account, uint256 amount)
        external
        virtual
        whenNotPaused
        returns (uint256 retirementEventId)
    {
        _spendAllowance(account, msg.sender, amount);
        retirementEventId = _retire(account, amount, account);
    }

    /// @notice Retire an amount of TCO2s, register a retirement event
    /// then mint a certificate passing a single retirementEventId.
    /// @param retiringEntityString An identifiable string for the retiring entity, eg. their name.
    /// @param beneficiary The beneficiary to set in the NFT.
    /// @param beneficiaryString The beneficiaryString to set in the NFT.
    /// @param retirementMessage The retirementMessage to set in the NFT.
    /// @param amount The amount to retire and issue an NFT certificate for.
    function retireAndMintCertificate(
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256 amount
    ) external virtual whenNotPaused {
        CreateRetirementRequestParams
            memory params = CreateRetirementRequestParams({
                tokenIds: new uint256[](0),
                amount: amount,
                retiringEntityString: retiringEntityString,
                beneficiary: beneficiary,
                beneficiaryString: beneficiaryString,
                retirementMessage: retirementMessage,
                beneficiaryLocation: '',
                consumptionCountryCode: '',
                consumptionPeriodStart: 0,
                consumptionPeriodEnd: 0
            });

        _retireAndMintCertificate(msg.sender, params);
    }
}
