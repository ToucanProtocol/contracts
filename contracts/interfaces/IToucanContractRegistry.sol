// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

interface IToucanContractRegistry {
    function carbonOffsetBatchesAddress() external view returns (address);

    function carbonProjectsAddress() external view returns (address);

    function carbonProjectVintagesAddress() external view returns (address);

    function toucanCarbonOffsetsFactoryAddress(string memory standardRegistry)
        external
        view
        returns (address);

    function retirementCertificatesAddress() external view returns (address);

    function toucanCarbonOffsetsEscrowAddress() external view returns (address);

    function retirementCertificateSlicerAddress()
        external
        view
        returns (address);

    function retirementCertificateSlicesAddress()
        external
        view
        returns (address);

    function isValidERC20(address erc20) external view returns (bool);

    function addERC20(address erc20, string memory standardRegistry) external;
}
