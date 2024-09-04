// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

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
error WITHDRAW_FAILED();
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
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
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
     * @notice Initializes the contract with the given manager, avatar NFT address, and payment token address.
     * @param _manager The address of the manager.
     * @param _mintNFT The address of the Avatar NFT contract.
     * @param _paymentToken The address of the payment token contract.
     */
    function initialize(
        address _manager,
        address _mintNFT,
        address _paymentToken
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, _manager);

        mintNFT = IMintNFT(_mintNFT);
        paymentToken = IERC20(_paymentToken);
        maxMintPerWallet = 20;
    }

    /**
     * @notice Sets a single tier with the given index, price, and ranges.
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
     * @notice Sets multiple tiers with the given indexes, prices, and ranges.
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
     * @notice Sets the maximum number of mints allowed per wallet.
     * @param _maxMintPerWallet The maximum number of mints per wallet.
     */
    function setMaxMintPerWallet(
        uint8 _maxMintPerWallet
    ) external onlyRole(MANAGER_ROLE) {
        maxMintPerWallet = _maxMintPerWallet;
    }

    /**
     * @notice Sets the address of the Avatar NFT contract.
     * @param _mintNFT The address of the Avatar NFT contract.
     */
    function setMintNFT(address _mintNFT) external onlyRole(MANAGER_ROLE) {
        mintNFT = IMintNFT(_mintNFT);
    }

    /**
     * @notice Sets the address of the payment token contract.
     * @param _paymentToken The address of the payment token contract.
     */
    function setPaymentToken(
        address _paymentToken
    ) external onlyRole(MANAGER_ROLE) {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @notice Withdraws tokens from the contract to the specified treasury address.
     * @param _token The address of the token to withdraw.
     * @param _treasury The address of the treasury to receive the tokens.
     */
    function withdrawFunds(
        address _token,
        address _treasury
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount == 0) revert ZERO_BALANCE();
        if (!IERC20(_token).transfer(_treasury, _amount))
            revert WITHDRAW_FAILED();
        emit FundsWithdrawn(_token, _treasury, _amount);
    }

    /**
     * @notice Mints a new token to the specified address.
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
     * @notice Mints multiple tokens to the specified address.
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
            emit TokenMinted(_to, _tokenIds[i]);
        }
    }

    /**
     * @notice Returns the address of the payment token contract.
     * @return The address of the payment token contract.
     */
    function getPaymentToken() external view returns (address) {
        return address(paymentToken);
    }

    /**
     * @notice Returns the address of the Avatar NFT contract.
     * @return The address of the Avatar NFT contract.
     */
    function getMintNFT() external view returns (address) {
        return address(mintNFT);
    }

    /**
     * @notice Returns the tier index for the given token ID.
     * @param _tokenId ID of the token.
     * @return The index of the tier.
     */
    function getTokenTier(uint256 _tokenId) external view returns (uint8) {
        return _getTokenTier(_tokenId);
    }

    /**
     * @notice Returns the price for the given token ID.
     * @param _tokenId The ID of the token.
     * @return The price of the token.
     */
    function getTokenPrice(uint256 _tokenId) external view returns (uint256) {
        return _getPrice(_tokenId);
    }

    /**
     * @notice Returns the tier at the specified index.
     * @param _index The index of the tier.
     * @return The tier at the specified index.
     */
    function getTier(uint8 _index) external view returns (Tier memory) {
        return tiers[_index];
    }

    /**
     * @notice Internal function to set a tier with the given index, price, and ranges.
     * @param _index The index of the tier.
     * @param _price The price of the tier.
     * @param _ranges The ranges of the tier.
     */
    function _setTier(
        uint8 _index,
        uint256 _price,
        uint256[2][] memory _ranges
    ) internal {
        Tier storage tier = tiers[_index];
        tier.price = _price;
        tier.ranges = new uint256[2][](0);
        for (uint256 i = 0; i < _ranges.length; i++) {
            tier.ranges.push(_ranges[i]);
        }
        emit TierSet(_index, _price, _ranges);
    }

    /**
     * @notice Internal function to get the price for the given token ID.
     * @param _tokenId The ID of the token.
     * @return The price of the token.
     */
    function _getPrice(uint256 _tokenId) internal view returns (uint256) {
        uint8 tierIndex = _getTokenTier(_tokenId);
        uint256 price = tiers[tierIndex].price;
        return price;
    }

    /**
     * @notice Internal function to get the tier index for the given token ID.
     * @param _tokenId The ID of the token.
     * @return The index of the tier.
     */
    function _getTokenTier(uint256 _tokenId) internal view returns (uint8) {
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            if (tiers[i].price > 0) {
                if (_binarySearch(tiers[i].ranges, _tokenId)) {
                    return i;
                }
            }
        }
        revert INVALID_TIER();
    }

    /**
     * @notice Internal function to check if the token ID is within the specified ranges.
     * @param ranges The ranges to check.
     * @param tokenId The ID of the token.
     * @return True if the token ID is within the ranges, false otherwise.
     */
    function _binarySearch(
        uint256[2][] storage ranges,
        uint256 tokenId
    ) internal view returns (bool) {
        uint256 low = 0;
        uint256 high = ranges.length - 1;

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            if (tokenId >= ranges[mid][0] && tokenId <= ranges[mid][1]) {
                return true;
            } else if (tokenId < ranges[mid][0]) {
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }
        return false;
    }

    /**
     * @notice Pauses all token transfers.
     */
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers.
     */
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
