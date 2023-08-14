// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import './ToucanCarbonOffsetsBase.sol';

/// @notice Base contract for any TCO2 token that can be retired
/// directly on-chain.
abstract contract ToucanCarbonOffsetsRetirements is ToucanCarbonOffsetsBase {
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event Retired(address sender, uint256 amount, uint256 eventId);

    // ----------------------------------------
    //              Functions
    // ----------------------------------------

    /// @notice Retirement/Cancellation of TCO2 tokens (the actual offsetting),
    /// which results in the tokens being burnt
    function retire(uint256 amount)
        public
        virtual
        whenNotPaused
        returns (uint256 retirementEventId)
    {
        retirementEventId = _retire(msg.sender, amount);
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
        retirementEventId = _retire(account, amount);
    }

    /// @dev Internal function for the burning of TCO2 tokens
    function _retire(address account, uint256 amount)
        internal
        virtual
        returns (uint256 retirementEventId)
    {
        _burn(account, amount);

        // Register retirement event in the certificates contract
        address certAddr = IToucanContractRegistry(contractRegistry)
            .retirementCertificatesAddress();
        retirementEventId = IRetirementCertificates(certAddr).registerEvent(
            account,
            projectVintageTokenId,
            amount,
            false
        );

        emit Retired(account, amount, retirementEventId);
    }

    /// @notice Retire an amount of TCO2s, register an retirement event
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
        // Retire provided amount
        uint256 retirementEventId = retire(amount);
        uint256[] memory retirementEventIds = new uint256[](1);
        retirementEventIds[0] = retirementEventId;

        // Mint certificate
        address certAddr = IToucanContractRegistry(contractRegistry)
            .retirementCertificatesAddress();
        //slither-disable-next-line unused-return
        IRetirementCertificates(certAddr).mintCertificate(
            msg.sender, /// @dev retiringEntity set automatically
            retiringEntityString,
            beneficiary,
            beneficiaryString,
            retirementMessage,
            retirementEventIds
        );
    }
}
