// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IAvatarNFT.sol";

error INSUFFICIENT_BALANCE();
error PAYMENT_FAILED();
error INVALID_ARRAY_LENGTH();
error INVALID_TIER();

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
        Range[] ranges;
        uint256 price;
    }
    mapping(uint8 => Tier) public tiers;

    uint256 public constant MAX_TIERS = 20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
    }

    function setTier(
        uint8 index,
        uint256 price,
        Range[] memory ranges
    ) external onlyRole(MANAGER_ROLE) {
        _setTier(index, price, ranges);
    }

    // Function to set the tiers
    function setTiers(
        uint8[] memory indexes,
        uint256[] memory prices,
        Range[][] memory ranges
    ) external onlyRole(MANAGER_ROLE) {
        require(
            indexes.length == prices.length && indexes.length == ranges.length,
            "INVALID_ARRAY_LENGTH"
        );
        for (uint256 i = 0; i < indexes.length; i++) {
            _setTier(indexes[i], prices[i], ranges[i]);
        }
    }

    function getTier(uint256 tokenId) external view returns (uint8) {
        return _getTier(tokenId);
    }

    function getPrice(uint256 tokenId) external view returns (uint256) {
        return _getPrice(tokenId);
    }

    function setavatarNFTAddress(
        address avatarNFTAddress
    ) external onlyRole(MANAGER_ROLE) {
        avatarNFT = IAvatarNFT(avatarNFTAddress);
    }

    function setPaymentTokenAddress(
        address paymentTokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        paymentToken = IERC20(paymentTokenAddress);
    }

    function mint(address to, uint256 tokenId) external {
        uint256 price = _getPrice(tokenId);

        if (paymentToken.balanceOf(msg.sender) < price)
            revert INSUFFICIENT_BALANCE();

        if (!paymentToken.transferFrom(msg.sender, address(this), price))
            revert PAYMENT_FAILED();

        avatarNFT.mint(to, tokenId);
    }

    function bulkMint(
        address[] calldata to,
        uint256[] calldata tokenIds,
        uint256[] calldata quantities
    ) external {
        if (to.length != tokenIds.length || to.length != quantities.length)
            revert INVALID_ARRAY_LENGTH();

        uint256 totalPrice = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalPrice += _getPrice(tokenIds[i]) * quantities[i];
        }

        if (paymentToken.balanceOf(msg.sender) < totalPrice)
            revert INSUFFICIENT_BALANCE();

        if (!paymentToken.transferFrom(msg.sender, address(this), totalPrice))
            revert PAYMENT_FAILED();

        for (uint256 i = 0; i < to.length; i++) {
            for (uint256 j = 0; j < quantities[i]; j++) {
                avatarNFT.mint(to[i], tokenIds[i]);
            }
        }
    }

    function _setTier(
        uint8 index,
        uint256 price,
        Range[] memory ranges
    ) internal {
        Tier storage tier = tiers[index];
        delete tier.ranges;
        for (uint256 i = 0; i < ranges.length; i++) {
            tier.ranges.push(ranges[i]);
        }
        tier.price = price;
    }

    function _getPrice(uint256 tokenId) internal view returns (uint256) {
        uint8 tierIndex = _getTier(tokenId);
        uint256 price = tiers[tierIndex].price;
        if (price == 0) {
            revert INVALID_TIER();
        }
        return price;
    }

    function _getTier(uint256 tokenId) internal view returns (uint8) {
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            if (tiers[i].price > 0) {
                for (uint256 j = 0; j < tiers[i].ranges.length; j++) {
                    if (
                        tokenId >= tiers[i].ranges[j].start &&
                        tokenId <= tiers[i].ranges[j].end
                    ) {
                        return i;
                    }
                }
            }
        }
        revert INVALID_TIER();
    }

    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(MANAGER_ROLE) {}
}
