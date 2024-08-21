// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMintNFT is IERC721 {
    function mint(address user, uint256 tokenId) external;
}
