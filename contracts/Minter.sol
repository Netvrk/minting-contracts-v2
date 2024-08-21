// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IMintNFT.sol";

error INSUFFICIENT_BALANCE();
error NO_ALLOWANCE();
error PAYMENT_FAILED();
error INVALID_ARRAY_LENGTH();
error INVALID_TIER();
error MAX_MINT_PER_WALLET_EXCEEDED();
error ZERO_BALANCE();

contract Minter is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    IMintNFT private mintNFT;
    IERC20 private paymentToken;

    struct Range {
        uint256 start;
        uint256 end;
    }

    struct Tier {
        uint256 price;
        uint256[2][] ranges;
    }
    mapping(uint8 => Tier) private tiers;

    uint8 private constant MAX_TIERS = 20;
    uint8 private maxMintPerWallet;

    event TierSet(uint8 indexed index, uint256 price, uint256[2][] ranges);
    event TokenMinted(address indexed to, uint256 indexed tokenId);
    event FundsWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given manager, avatar NFT address, and payment token address.
     * Grants the DEFAULT_ADMIN_ROLE and MANAGER_ROLE to the deployer and the specified manager.
     * @param _manager The address of the manager.
     * @param _mintNFTAddress The address of the Avatar NFT contract.
     * @param _paymentTokenAddress The address of the payment token contract.
     */
    function initialize(
        address _manager,
        address _mintNFTAddress,
        address _paymentTokenAddress
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, _manager);

        mintNFT = IMintNFT(_mintNFTAddress);
        paymentToken = IERC20(_paymentTokenAddress);
        maxMintPerWallet = 20;
    }

    // Set functions

    /**
     * @dev Sets a single tier with the given index, price, and ranges.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param _index The index of the tier.
     * @param _price The price of the tier.
     * @param _ranges The ranges of the tier.
     */
    function setTier(
        uint8 _index,
        uint256 _price,
        uint256[2][] memory _ranges
    ) external onlyRole(MANAGER_ROLE) {
        if (_index >= MAX_TIERS) revert INVALID_TIER();
        _setTier(_index, _price, _ranges);
    }

    /**
     * @dev Sets multiple tiers with the given indexes, prices, and ranges.
     * Can only be called by an account with the MANAGER_ROLE.
     * Reverts if the lengths of the input arrays do not match.
     * @param _indexes The indexes of the tiers.
     * @param _prices The prices of the tiers.
     * @param _ranges The ranges of the tiers.
     */
    function setTiers(
        uint8[] memory _indexes,
        uint256[] memory _prices,
        uint256[2][][] memory _ranges
    ) external onlyRole(MANAGER_ROLE) {
        if (
            _indexes.length != _prices.length ||
            _indexes.length != _ranges.length
        ) revert INVALID_ARRAY_LENGTH();

        for (uint256 i = 0; i < _indexes.length; i++) {
            if (_indexes[i] >= MAX_TIERS) revert INVALID_TIER();
            _setTier(_indexes[i], _prices[i], _ranges[i]);
        }
    }

    /**
     * @dev Sets the maximum number of mints allowed per wallet.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param _maxMintPerWallet The maximum number of mints per wallet.
     */
    function setMaxMintPerWallet(
        uint8 _maxMintPerWallet
    ) external onlyRole(MANAGER_ROLE) {
        maxMintPerWallet = _maxMintPerWallet;
    }

    /**
     * @dev Sets the address of the Avatar NFT contract.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param _mintNFTAddress The address of the Avatar NFT contract.
     */
    function setMintNFTAddress(
        address _mintNFTAddress
    ) external onlyRole(MANAGER_ROLE) {
        mintNFT = IMintNFT(_mintNFTAddress);
    }

    /**
     * @dev Sets the address of the payment token contract.
     * Can only be called by an account with the MANAGER_ROLE.
     * @param _paymentTokenAddress The address of the payment token contract.
     */
    function setPaymentTokenAddress(
        address _paymentTokenAddress
    ) external onlyRole(MANAGER_ROLE) {
        paymentToken = IERC20(_paymentTokenAddress);
    }

    /**
     * @dev Withdraws tokens from the contract to the specified treasury address.
     * Can only be called by an account with the MANAGER_ROLE.
     * Reverts if the contract has zero balance of the specified token.
     * @param _token The address of the token to withdraw.
     * @param _treasury The address of the treasury to receive the tokens.
     */
    function withdrawFunds(
        address _token,
        address _treasury
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount == 0) revert ZERO_BALANCE();
        IERC20(_token).transfer(_treasury, _amount);
        emit FundsWithdrawn(_token, _treasury, _amount);
    }

    // Mint functions

    /**
     * @dev Mints a new token to the specified address.
     * Requires the caller to have sufficient balance of the payment token.
     * Reverts if the recipient has reached the maximum mint limit per wallet.
     * @param _to The address to mint the token to.
     * @param _tokenId The ID of the token to mint.
     */
    function mint(address _to, uint256 _tokenId) external nonReentrant {
        if (mintNFT.balanceOf(_to) >= maxMintPerWallet)
            revert MAX_MINT_PER_WALLET_EXCEEDED();

        uint256 price = _getPrice(_tokenId);

        if (paymentToken.balanceOf(msg.sender) < price)
            revert INSUFFICIENT_BALANCE();

        if (paymentToken.allowance(msg.sender, address(this)) < price)
            revert NO_ALLOWANCE();

        if (!paymentToken.transferFrom(msg.sender, address(this), price))
            revert PAYMENT_FAILED();

        mintNFT.mint(_to, _tokenId);

        emit TokenMinted(_to, _tokenId);
    }

    /**
     * @dev Mints multiple tokens to the specified address.
     * Requires the caller to have sufficient balance of the payment token.
     * Reverts if the recipient has reached the maximum mint limit per wallet.
     * @param _to The address to mint the tokens to.
     * @param _tokenIds The IDs of the tokens to mint.
     */
    function bulkMint(
        address _to,
        uint256[] calldata _tokenIds
    ) external nonReentrant {
        if (mintNFT.balanceOf(_to) + _tokenIds.length > maxMintPerWallet)
            revert MAX_MINT_PER_WALLET_EXCEEDED();

        uint256 totalPrice = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            totalPrice += _getPrice(_tokenIds[i]);
        }

        if (paymentToken.balanceOf(msg.sender) < totalPrice)
            revert INSUFFICIENT_BALANCE();

        if (!paymentToken.transferFrom(msg.sender, address(this), totalPrice))
            revert PAYMENT_FAILED();

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            mintNFT.mint(_to, _tokenIds[i]);
        }
    }

    // Get functions

    /**
     * @dev Returns the address payment token contract.
     * @return The address of the payment token contract.
     */
    function getPaymentToken() external view returns (address) {
        return address(paymentToken);
    }

    /**
     * @dev Returns the tier index for the given token ID.
     * @param _tokenId ID of the token.
     * @return The index of the tier.
     */
    function getTokenTier(uint256 _tokenId) external view returns (uint8) {
        return _getTokenTier(_tokenId);
    }

    /**
     * @dev Returns the price for the given token ID.
     * @param _tokenId The ID of the token.
     * @return The price of the token.
     */
    function getTokenPrice(uint256 _tokenId) external view returns (uint256) {
        return _getPrice(_tokenId);
    }

    /**
     * @dev Returns the tier at the specified index.
     * @param _index The index of the tier.
     * @return The tier at the specified index.
     */
    function getTier(uint8 _index) external view returns (Tier memory) {
        return tiers[_index];
    }

    // Internal functions

    /**
     * @dev Internal function to set a tier with _tokenIdven index, price, and ranges.
     * @param _index The index of the tier.
     * @param _price The price of the tier._tokenId
     * @param _ranges The ranges of the tier._tokenId
     */
    function _setTier(
        uint8 _index,
        uint256 _price,
        uint256[2][] memory _ranges
    ) internal {
        Tier storage tier = tiers[_index];
        tier.price = _price;
        delete tier.ranges;
        for (uint256 i = 0; i < _ranges.length; ) {
            tier.ranges.push(_ranges[i]);
            unchecked {
                i++;
            }
        }
        emit TierSet(_index, _price, _ranges);
    }

    /**
     * @dev Internal function to get the price for the given token ID.
     * Reverts if the tier is invalid.
     * @param _tokenId The ID of the token.
     * @return The price of the token.
     */
    function _getPrice(uint256 _tokenId) internal view returns (uint256) {
        uint8 tierIndex = _getTokenTier(_tokenId);
        uint256 price = tiers[tierIndex].price;
        if (price == 0) {
            revert INVALID_TIER();
        }
        return price;
    }

    /**
     * @dev Internal function to get the tier index for the given token ID.
     * Reverts if the tier is invalid.
     * @param _tokenId The ID of the token.
     * @return The index of the tier.
     */
    function _getTokenTier(uint256 _tokenId) internal view returns (uint8) {
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            if (tiers[i].price > 0) {
                for (uint256 j = 0; j < tiers[i].ranges.length; j++) {
                    if (
                        _tokenId >= tiers[i].ranges[j][0] &&
                        _tokenId <= tiers[i].ranges[j][1]
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
