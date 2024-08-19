// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import {CreateRetirementRequestParams} from '../bases/ToucanCarbonOffsetsWithBatchBaseTypes.sol';
import '../retirements/RetirementCertificatesTypes.sol';

interface IRetirementCertificates {
    function mintCertificate(
        address retiringEntity,
        string calldata retiringEntityString,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256[] calldata retirementEventIds
    ) external returns (uint256);

    function mintCertificateWithExtraData(
        address retiringEntity,
        CreateRetirementRequestParams calldata params,
        uint256[] calldata retirementEventIds
    ) external returns (uint256);

    function registerEvent(
        address retiringEntity,
        uint256 projectVintageTokenId,
        uint256 amount,
        bool isLegacy
    ) external returns (uint256 retireEventCounter);

    /// NOTE: This function is deprecated in favour of `certificates` and should be removed in future versions.
    function getData(uint256 tokenId)
        external
        view
        returns (CertificateData memory);

    function certificates(uint256 tokenId)
        external
        view
        returns (CertificateData memory);

    function retirements(uint256)
        external
        view
        returns (RetirementEvent memory);
}
