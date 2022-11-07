// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';

import '../CarbonProjectTypes.sol';

interface ICarbonProjects is IERC721Upgradeable {
    function getProjectId(uint256 tokenId)
        external
        view
        returns (string memory projectId);

    function addNewProject(
        address to,
        ProjectData calldata _projectData
    ) external returns (uint256);

    function isValidProjectTokenId(uint256 tokenId) external returns (bool);

    function getProjectDataByTokenId(uint256 tokenId)
        external
        view
        returns (ProjectData memory);
}
