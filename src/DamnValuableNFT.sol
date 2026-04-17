// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

/**
 * @title DamnValuableNFT
 * @notice Mintable and burnable NFT with role-based access controls.
 * @dev Extends OpenZeppelin's ERC721 and ERC721Burnable, and uses Solady's
 *      OwnableRoles for lightweight role management. Only accounts granted
 *      MINTER_ROLE can mint new tokens; burning is handled by ERC721Burnable
 *      (token owner or approved address can burn).
 */
contract DamnValuableNFT is ERC721, ERC721Burnable, OwnableRoles {

    /// @notice Role identifier for accounts permitted to mint new tokens.
    /// @dev Corresponds to _ROLE_0 in Solady's OwnableRoles bitmask system.
    uint256 public constant MINTER_ROLE = _ROLE_0;

    /// @notice Auto-incrementing counter used as the next token ID.
    /// @dev Starts at 0. Incremented after every successful mint.
    uint256 public nonce;

    /**
     * @notice Deploys the NFT contract, granting the deployer both ownership
     *         and MINTER_ROLE.
     * @dev Calls ERC721 constructor with a fixed name and symbol.
     *      OwnableRoles._initializeOwner sets msg.sender as the contract owner.
     *      _grantRoles additionally gives msg.sender minting privileges.
     */
    constructor() ERC721("DamnValuableNFT", "DVNFT") {
        // Set the contract deployer as the owner (Solady OwnableRoles)
        _initializeOwner(msg.sender);

        // Grant the deployer the MINTER_ROLE so they can immediately mint tokens
        _grantRoles(msg.sender, MINTER_ROLE);
    }

    /**
     * @notice Mints a new token to the specified address.
     * @dev Uses the current value of `nonce` as the token ID, then increments it.
     *      Calls OpenZeppelin's _safeMint, which verifies that `to` can receive
     *      ERC721 tokens (i.e., if `to` is a contract, it must implement
     *      IERC721Receiver). Reverts if the caller does not hold MINTER_ROLE.
     * @param to The address that will receive the newly minted token.
     * @return tokenId The ID of the newly minted token (equal to the pre-increment nonce).
     */
    function safeMint(address to) public onlyRoles(MINTER_ROLE) returns (uint256 tokenId) {
        // Capture the current nonce as the token ID before incrementing
        tokenId = nonce;

        // Safely mint the token — reverts if `to` is a contract that rejects ERC721
        _safeMint(to, tokenId);

        // Increment the nonce so the next mint uses a unique ID
        ++nonce;
    }
}
