// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

interface IToucanPoolTest {
    function getScoredTCO2s() external view returns (address[] memory);

    function redeemAuto(uint256 amount) external;

    function redeemAuto2(uint256 amount)
        external
        returns (address[] memory, uint256[] memory);
}

interface IToucanCarbonOffsetsTest {
    function retire(uint256 amount) external;
}

/// Example contract that performs carbon retirement fully on-chain
/// Meant to be used as a gas benchmark for the different redeemAuto
/// implementations.
contract CarbonBurnTest {
    address public _poolToken;

    constructor(address poolToken) {
        _poolToken = poolToken;
    }

    function testRedeemAuto(uint256 _totalAmount) external {
        address[] memory listTCO2 = IToucanPoolTest(_poolToken)
            .getScoredTCO2s();

        // Redeem pool tokens
        IToucanPoolTest(_poolToken).redeemAuto(_totalAmount);

        // Retire TCO2
        for (uint256 i = 0; _totalAmount > 0; i++) {
            uint256 balance = IERC20Upgradeable(listTCO2[i]).balanceOf(
                address(this)
            );

            IToucanCarbonOffsetsTest(listTCO2[i]).retire(balance);
            _totalAmount -= balance;
        }
    }

    function testRedeemAuto2(uint256 _totalAmount) external {
        // Redeem pool tokens
        (address[] memory tco2s, uint256[] memory amounts) = IToucanPoolTest(
            _poolToken
        ).redeemAuto2(_totalAmount);

        // Retire TCO2
        for (uint256 i = 0; i < tco2s.length; i++) {
            if (amounts[i] < 1e15) {
                // Dust check for less than a kilo amounts.
                // These are invalid retirements since the retirement
                // certificate's smallest denomination is in kilos.
                continue;
            }
            IToucanCarbonOffsetsTest(tco2s[i]).retire(amounts[i]);
        }
    }
}
