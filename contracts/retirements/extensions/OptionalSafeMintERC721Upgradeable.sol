// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {ERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import {IERC721Receiver} from '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

/**
 * @title OptionalSafeMintERC721Upgradeable
 * @notice Extension for ERC721 that adds an optional safe mint function where the receiver check can be made non-reverting.
 * The main use case for skipping reverts is in case ERC721 token minters want to mint at all times and not depend on client developers
 * to ensure that they can receive these tokens. Furthermore, it is not possible to distinguish between the lack of a receiver or a faulty
 * receiver and a receiver that intentionally reverts or returns false so this extension should be used with caution.
 */
abstract contract OptionalSafeMintERC721Upgradeable is ERC721Upgradeable {
    using AddressUpgradeable for address;

    /**
     * @notice Safely mints a token with optional revert behavior on receiver check failure
     * @param to The address to mint to
     * @param tokenId The token ID to mint
     * @param data Additional data to pass to the receiver
     * @param skipRevert If true, skips reverting at the receiver check. If false, reverts when receiver check fails
     */
    function _optionalSafeMint(
        address to,
        uint256 tokenId,
        bytes memory data,
        bool skipRevert
    ) internal virtual {
        _mint(to, tokenId);
        _checkOnERC721Received(address(0), to, tokenId, data, skipRevert);
    }

    /**
     * @notice Overload that allows optional safe minting without data
     * @param to The address to mint to
     * @param tokenId The token ID to mint
     * @param skipRevert If true, skips reverting at the receiver check. If false, reverts when receiver check fails
     */
    function _optionalSafeMint(
        address to,
        uint256 tokenId,
        bool skipRevert
    ) internal virtual {
        _optionalSafeMint(to, tokenId, '', skipRevert);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @param skipRevert If true, skips reverting at the receiver check. If false, reverts when receiver check fails
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data,
        bool skipRevert
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IERC721Receiver(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (skipRevert) {
                    return false;
                }
                if (reason.length == 0) {
                    revert(
                        'ERC721: transfer to non ERC721Receiver implementer'
                    );
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}
