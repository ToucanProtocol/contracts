// SPDX-FileCopyrightText: 2023 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

abstract contract RoleInitializer is AccessControlUpgradeable {
    function __RoleInitializer_init_unchained(
        address[] calldata accounts,
        bytes32[] calldata roles
    ) internal {
        require(accounts.length == roles.length, 'Array length mismatch');

        __AccessControl_init_unchained();

        bool hasDefaultAdmin = false;
        for (uint256 i = 0; i < accounts.length; ++i) {
            _grantRole(roles[i], accounts[i]);
            if (roles[i] == DEFAULT_ADMIN_ROLE) hasDefaultAdmin = true;
        }
        require(hasDefaultAdmin, 'No admin specified');
    }
}
