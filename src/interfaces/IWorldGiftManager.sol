// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IWorldGiftManager {
    /// @notice Emitted when a gift is created
    /// @param giftId The ID of the created gift
    /// @param token The address of the token to gift
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens gifted
    event GiftCreated(
        uint256 indexed giftId,
        address indexed token,
        address indexed sender,
        address recipient,
        uint256 amount
    );

    /// @notice Emitted when a gift is redeemed
    /// @param giftId The ID of the redeemed gift
    /// @param token The address of the token redeemed
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens redeemed
    event GiftRedeemed(
        uint256 indexed giftId,
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Represents a gift of tokens
    /// @param recipient The address of the gift recipient
    /// @param token The address of the ERC20 token being gifted
    /// @param amount The amount of tokens gifted
    /// @param redeemed Whether the gift has been redeemed
    struct Gift {
        address recipient;
        address token;
        uint256 amount;
        bool redeemed;
    }

    function getGift(uint256 giftId) external view returns (Gift memory);
    function isTokenAllowed(address token) external view returns (bool);

    /// @notice Gift tokens to a recipient
    /// @param token The ERC20 token to gift
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens to gift
    /// @custom:throws InvalidAmount if the amount is zero
    /// @custom:throws InvalidRecipient if the recipient is the sender or zero address
    /// @return giftId The ID of the created gift
    function gift(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount
    ) public returns (uint256 giftId);

    /// @notice Redeem a gifted token
    /// @param giftId The ID of the gift to redeem
    /// @custom:throws GiftNotFound if the gift does not exist
    /// @custom:throws NotVerified if the recipient is not verified
    /// @custom:throws AlreadyRedeemed if the gift has already been redeemed
    function redeem(uint256 giftId) public;
}
