// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IAvatarNFT.sol";
import "hardhat/console.sol";

error INSUFFICIENT_BALANCE();
error PAYMENT_FAILED();
error INVALID_ARRAY_LENGTH();
error INVALID_TIER();
error MAX_MINT_PER_WALLET_EXCEEDED();

contract Minter is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    IAvatarNFT private avatarNFT;
    IERC20 public paymentToken;

    struct Range {
        uint256 start;
        uint256 end;
    }
    struct Tier {
        uint256 price;
        uint256[2][] ranges;
    }
    mapping(uint8 => Tier) public tiers;

    uint256 public constant MAX_TIERS = 20;
    uint256 public maxMintPerWallet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given manager, avatar NFT address, and payment token address.
     * Grants the DEFAULT_ADMIN_ROLE and MANAGER_ROLE to the deployer and the specified manager.
     * @param manager The address of the manager.
     * @param avatarNFTAddress The address of the Avatar NFT contract.
     * @param paymentTokenAddress The address of the payment token contract.
     */
    function initialize(
        address manager,
        address avatarNFTAddress,
        address paymentTokenAddress
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, manager);

        avatarNFT = IAvatarNFT(avatarNFTAddress);
        paymentToken = IERC20(paymentTokenAddress);
        maxMintPerWallet = 20;
    }

    // Set functions

    /**
     * @dev Sets a single tier with the given index, price, and ranges.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param index The index of the tier.
     * @param price The price of the tier.
     * @param ranges The ranges of the tier.
     */
    function setTier(
        uint8 index,
        uint256 price,
        uint256[2][] memory ranges
    ) external onlyRole(MANAGER_ROLE) {
        _setTier(index, price, ranges);
    }

    /**
     * @dev Sets multiple tiers with the given indexes, prices, and ranges.
     * Can only be called by an account with the MANAGER_ROLE.
     * Reverts if the lengths of the input arrays do not match.
     * @param indexes The indexes of the tiers.
     * @param prices The prices of the tiers.
     * @param ranges The ranges of the tiers.
     */
    function setTiers(
        uint8[] memory indexes,
        uint256[] memory prices,
        uint256[2][][] memory ranges
    ) external onlyRole(MANAGER_ROLE) {
        if (indexes.length != prices.length || indexes.length != ranges.length)
            revert INVALID_ARRAY_LENGTH();

        for (uint256 i = 0; i < indexes.length; i++) {
            _setTier(indexes[i], prices[i], ranges[i]);
        }
    }

    /**
     * @dev Sets the maximum number of mints allowed per wallet.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param _maxMintPerWallet The maximum number of mints per wallet.
     */
    function setMaxMintPerWallet(
        uint256 _maxMintPerWallet
    ) external onlyRole(MANAGER_ROLE) {
        maxMintPerWallet = _maxMintPerWallet;
    }

    /**
     * @dev Sets the address of the Avatar NFT contract.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param avatarNFTAddress The address of the Avatar NFT contract.
     */
    function setavatarNFTAddress(
        address avatarNFTAddress
    ) external onlyRole(MANAGER_ROLE) {
        avatarNFT = IAvatarNFT(avatarNFTAddress);
    }

    /**
     * @dev Sets the address of the payment token contract.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param paymentTokenAddress The address of the payment token contract.
     */
    function setPaymentTokenAddress(
        address paymentTokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        paymentToken = IERC20(paymentTokenAddress);
    }

    // Mint functions

    /**
     * @dev Mints a new token to the specified address.
     * Requires the caller to have sufficient balance of the payment token.
     * Reverts if the recipient has reached the maximum mint limit per wallet.
     * @param to The address to mint the token to.
     * @param tokenId The ID of the token to mint.
     */
    function mint(address to, uint256 tokenId) external {
        if (avatarNFT.balanceOf(to) >= maxMintPerWallet)
            revert MAX_MINT_PER_WALLET_EXCEEDED();

        uint256 price = _getPrice(tokenId);

        if (paymentToken.balanceOf(msg.sender) < price)
            revert INSUFFICIENT_BALANCE();

        if (!paymentToken.transferFrom(msg.sender, address(this), price))
            revert PAYMENT_FAILED();

        avatarNFT.mint(to, tokenId);
    }

    /**
     * @dev Mints multiple tokens to the specified address.
     * Requires the caller to have sufficient balance of the payment token.
     * @param to The address to mint the tokens to.
     * @param tokenIds The IDs of the tokens to mint.
     */
    function bulkMint(address to, uint256[] calldata tokenIds) external {
        if (avatarNFT.balanceOf(to) + tokenIds.length > maxMintPerWallet)
            revert MAX_MINT_PER_WALLET_EXCEEDED();

        uint256 totalPrice = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalPrice += _getPrice(tokenIds[i]);
        }

        if (paymentToken.balanceOf(msg.sender) < totalPrice)
            revert INSUFFICIENT_BALANCE();

        if (!paymentToken.transferFrom(msg.sender, address(this), totalPrice))
            revert PAYMENT_FAILED();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            avatarNFT.mint(to, tokenIds[i]);
        }
    }

    // Get functions

    /**
     * @dev Returns the tier index for the given token ID.
     * @param tokenId The ID of the token.
     * @return The index of the tier.
     */
    function getTokenTier(uint256 tokenId) external view returns (uint8) {
        return _getTokenTier(tokenId);
    }

    /**
     * @dev Returns the price for the given token ID.
     * @param tokenId The ID of the token.
     * @return The price of the token.
     */
    function getTokenPrice(uint256 tokenId) external view returns (uint256) {
        return _getPrice(tokenId);
    }

    /**
     * @dev Returns the tier at the specified index.
     * @param index The index of the tier.
     * @return The tier at the specified index.
     */
    function getTier(uint8 index) external view returns (Tier memory) {
        return tiers[index];
    }

    // Internal functions

    /**
     * @dev Internal function to set a tier with the given index, price, and ranges.
     * @param index The index of the tier.
     * @param price The price of the tier.
     * @param ranges The ranges of the tier.
     */
    function _setTier(
        uint8 index,
        uint256 price,
        uint256[2][] memory ranges
    ) internal {
        Tier storage tier = tiers[index];
        delete tier.ranges;
        for (uint256 i = 0; i < ranges.length; i++) {
            tier.ranges.push(ranges[i]);
        }
        tier.price = price;
    }

    /**
     * @dev Internal function to get the price for the given token ID.
     * Reverts if the tier is invalid.
     * @param tokenId The ID of the token.
     * @return The price of the token.
     */
    function _getPrice(uint256 tokenId) internal view returns (uint256) {
        uint8 tierIndex = _getTokenTier(tokenId);
        uint256 price = tiers[tierIndex].price;
        if (price == 0) {
            revert INVALID_TIER();
        }
        return price;
    }

    /**
     * @dev Internal function to get the tier index for the given token ID.
     * Reverts if the tier is invalid.
     * @param tokenId The ID of the token.
     * @return The index of the tier.
     */
    function _getTokenTier(uint256 tokenId) internal view returns (uint8) {
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            if (tiers[i].price > 0) {
                for (uint256 j = 0; j < tiers[i].ranges.length; j++) {
                    if (
                        tokenId >= tiers[i].ranges[j][0] &&
                        tokenId <= tiers[i].ranges[j][1]
                    ) {
                        return i;
                    }
                }
            }
        }
        revert INVALID_TIER();
    }

    // Pause and upgrade functions (Inheritance)

    /**
     * @dev Pauses all token transfers.
     * Can only be called by an account with the MANAGER_ROLE.
     */
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     * Can only be called by an account with the MANAGER_ROLE.
     */
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorizes an upgrade to a new implementation.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(MANAGER_ROLE) {}
}
