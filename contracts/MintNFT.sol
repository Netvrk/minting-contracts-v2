// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MintNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC721("MintNFT", "mNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://example.com/";
    }

    function mint(address to, uint256 tokenId) public onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
