// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

import '../interfaces/IRetirementCertificates.sol';

interface IToucanPoolTest {
    function getScoredTCO2s() external view returns (address[] memory);

    function redeemAuto(uint256 amount) external;

    function redeemAuto2(uint256 amount)
        external
        returns (address[] memory, uint256[] memory);

    function redeemAndRetireMany(
        address[] memory tco2s,
        uint256[] memory amounts
    )
        external
        returns (
            uint256[] memory retirementIds,
            uint256[] memory redeemedAmounts
        );

    function redeemMany(address[] memory tco2s, uint256[] memory amounts)
        external
        returns (uint256[] memory redeemedAmounts);

    function feeRedeemPercentageInBase() external view returns (uint256);
}

interface IToucanCarbonOffsetsTest {
    function retire(uint256 amount) external;

    function approve(address spender, uint256 amount) external returns (bool);
}

/// Example contract that performs carbon retirement fully on-chain
/// Meant to be used to test various composability scenarios between
/// pool and TCO2 functions
contract PoolComposabilityTest {
    address public immutable _poolToken;
    address public immutable _retirementCertificates;

    constructor(address poolToken, address retirementCertificates) {
        _poolToken = poolToken;
        _retirementCertificates = retirementCertificates;
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

    function testRedeemAuto2(uint256 _totalAmount, uint256 expectedLength)
        external
    {
        // Redeem pool tokens
        (address[] memory tco2s, uint256[] memory amounts) = IToucanPoolTest(
            _poolToken
        ).redeemAuto2(_totalAmount);

        require(tco2s.length == expectedLength, 'Unexpected tco2 length');
        require(amounts.length == expectedLength, 'Unexpected amounts length');

        // Retire TCO2
        for (uint256 i = 0; i < tco2s.length; i++) {
            IToucanCarbonOffsetsTest(tco2s[i]).retire(amounts[i]);
        }
    }

    function testRedeemManyArgs(
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external {
        uint256[] memory redeemedAmounts = IToucanPoolTest(_poolToken)
            .redeemMany(tco2s, amounts);

        uint256 feeRedeemPercentageInBase = IToucanPoolTest(_poolToken)
            .feeRedeemPercentageInBase();
        for (uint256 i = 0; i < redeemedAmounts.length; ++i) {
            uint256 expectedAmount = amounts[i] -
                ((amounts[i] * feeRedeemPercentageInBase) / 1e4);
            require(
                redeemedAmounts[i] == expectedAmount,
                'Unexpected redeemed amount'
            );
        }
    }

    function testRedeemRetireAndMintCertificate(
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external {
        // for all tco2s and amounts we need to approve the pool to spend them
        for (uint256 i = 0; i < tco2s.length; ++i) {
            require(
                IToucanCarbonOffsetsTest(tco2s[i]).approve(
                    _poolToken,
                    amounts[i]
                )
            );
        }

        // redeem and retire from the pool
        (uint256[] memory retirementIds, ) = IToucanPoolTest(_poolToken)
            .redeemAndRetireMany(tco2s, amounts);

        // mint certificate for the retirements we just did
        uint256 tokenId = IRetirementCertificates(_retirementCertificates)
            .mintCertificate(
                address(this),
                'Testing Contract',
                msg.sender,
                'Tester',
                'Just testing',
                retirementIds
            );
        IRetirementCertificates(_retirementCertificates).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
    }

    function testRedeemRetireAndMintCertificateN(
        address[] calldata tco2s,
        uint256[] calldata amounts
    ) external {
        // for all tco2s and amounts we need to approve the pool to spend them
        for (uint256 i = 0; i < tco2s.length; ++i) {
            require(
                IToucanCarbonOffsetsTest(tco2s[i]).approve(
                    _poolToken,
                    amounts[i]
                )
            );
        }

        // redeem and retire from the pool
        (uint256[] memory retirementIds, ) = IToucanPoolTest(_poolToken)
            .redeemAndRetireMany(tco2s, amounts);

        // mint certificates for the retirements we just did
        for (uint256 i = 0; i < retirementIds.length; ++i) {
            uint256[] memory ids = new uint256[](1);
            ids[0] = retirementIds[i];
            uint256 tokenId = IRetirementCertificates(_retirementCertificates)
                .mintCertificate(
                    address(this),
                    'Testing Contract',
                    msg.sender,
                    'Tester',
                    'Just testing',
                    ids
                );
            IRetirementCertificates(_retirementCertificates).safeTransferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }
    }

    // Implement the ERC721Receiver interface
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
