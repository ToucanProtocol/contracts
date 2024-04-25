// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

interface IPoolFilter {
    function checkEligible(address erc20Addr) external view returns (bool);

    function checkERC1155Eligible(address token, uint256 tokenId)
        external
        view
        returns (bool);

    function minimumVintageStartTime() external view returns (uint64);

    function regions(string calldata region) external view returns (bool);

    function standards(string calldata standard) external view returns (bool);

    function methodologies(string calldata methodology)
        external
        view
        returns (bool);
}
