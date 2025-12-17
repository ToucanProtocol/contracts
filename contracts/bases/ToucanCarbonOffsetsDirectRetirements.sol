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
        retirementEventId = _retire(msg.sender, amount, msg.sender, '');
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
        retirementEventId = _retire(account, amount, account, '');
    }

    /// @notice Retire an amount of TCO2s and mint a RetirementCertificate NFT.
    /// Note that this information is publicly written to the blockchain in plaintext.
    /// @param retiringEntityString An identifiable string for the retiring entity, eg. their name
    /// @param beneficiary The address of the beneficiary of the retirement
    /// @param beneficiaryString An identifiable string for the beneficiary, eg. their name
    /// @param retirementMessage A message to be included in the retirement certificate
    /// @param amount The amount to retire and issue an NFT certificate for
    function retireAndMintCertificate(
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256 amount
    ) external virtual whenNotPaused {
        uint256 retirementEventId = _retire(msg.sender, amount, msg.sender, '');
        uint256[] memory retirementEventIds = new uint256[](1);
        retirementEventIds[0] = retirementEventId;

        //slither-disable-next-line unused-return
        IRetirementCertificates(
            IToucanContractRegistry(contractRegistry)
                .retirementCertificatesAddress()
        ).mintCertificate(
                msg.sender,
                retiringEntityString,
                beneficiary,
                beneficiaryString,
                retirementMessage,
                retirementEventIds
            );
    }
}
