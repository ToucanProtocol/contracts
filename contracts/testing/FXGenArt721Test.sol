// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {ERC721, IERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

import {IFxGenArt721} from '../periphery/FxHashNFTCarbonExtension.sol';

/**
 * @title FxGenArt721
 * @author fx(hash)
 * @notice See the documentation in {IFxGenArt721}
 */
contract FxGenArt721Test is IFxGenArt721, ERC721 {
    uint96 public totalSupply;

    constructor() ERC721('FxGenArt721', 'FXHASH') {}

    function mint(
        address _to,
        uint256 _amount,
        uint256 /* _payment */
    ) external {
        uint96 currentId = totalSupply;
        for (uint256 i; i < _amount; ++i) {
            _mint(_to, ++currentId);
        }
        totalSupply = currentId;
    }

    /**
     * @inheritdoc ERC721
     */
    function tokenURI(uint256 _tokenId)
        public
        pure
        override
        returns (string memory)
    {
        return
            string(
                abi.encodePacked('https://test/', Strings.toString(_tokenId))
            );
    }
}
