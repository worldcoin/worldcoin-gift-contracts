// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IAddressBook} from "./interfaces/IAddressBook.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title World Gift Manager
/// @author Miguel Piedrafita
/// @notice Allows World App users to send and redeem token gifts
contract WorldGiftManager is Ownable {
    ///////////////////////////////////////////////////////////////////////////////
    ///                                  ERRORS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when the contract is misconfigured
    error InvalidConfiguration();

    /// @notice Thrown when an unverified recipient attempts to redeem a gift
    error NotVerified();

    /// @notice Thrown when trying to redeem a non-existent gift
    error GiftNotFound();

    /// @notice Thrown when trying to redeem a gift that has already been redeemed
    error AlreadyRedeemed();

    /// @notice Thrown when trying to create a gift with an invalid recipient
    error InvalidRecipient();

    /// @notice Thrown when trying to create a gift with an invalid amount
    error InvalidAmount();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the contract is initialized
    /// @param token The address of the token contract
    /// @param addressBook The address of the address book contract
    event WorldGiftManagerInitialized(
        IERC20 indexed token,
        IAddressBook indexed addressBook
    );

    /// @notice Emitted when a gift is created
    /// @param giftId The ID of the created gift
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens gifted
    event GiftCreated(
        uint256 indexed giftId,
        address indexed sender,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a gift is redeemed
    /// @param giftId The ID of the redeemed gift
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens redeemed
    event GiftRedeemed(
        uint256 indexed giftId,
        address indexed recipient,
        uint256 amount
    );

    ///////////////////////////////////////////////////////////////////////////////
    ///                            TYPE DECLARATIONS                            ///
    //////////////////////////////////////////////////////////////////////////////

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

    ///////////////////////////////////////////////////////////////////////////////
    ///                              CONFIG STORAGE                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice The address book contract that will be used to check verification status
    IAddressBook public addressBook;

    /// @notice The next gift ID to be assigned
    uint256 private nextGiftId = 1;

    /// @notice A mapping of gift IDs to Gift structs
    mapping(uint256 => Gift) public getGift;

    /// @notice A mapping of allowed ERC20 tokens
    mapping(address => bool) public isTokenAllowed;

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONSTRUCTOR                              ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Create a new WorldGiftManager contract
    /// @param _addressBook The AddressBook contract for verification checks
    constructor(IAddressBook _addressBook) {
        require(address(_addressBook) != address(0), InvalidConfiguration());

        addressBook = _addressBook;

        _initializeOwner(msg.sender);

        emit WorldGiftManager.WorldGiftManagerInitialized(token, addressBook);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               MAIN LOGIC                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Gift tokens to a recipient
    /// @param token The ERC20 token to gift
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens to gift
    /// @custom:throws InvalidAmount if the amount is zero
    /// @custom:throws InvalidRecipient if the recipient is the sender or zero address
    /// @return giftId The ID of the created gift
    function gift(
        IERC20 token,
        address recipient,
        uint256 amount
    ) public returns (uint256 giftId) {
        require(amount > 0, InvalidAmount());
        require(recipient != address(0), InvalidRecipient());

        unchecked {
            giftId = nextGiftId++;
        }

        getGift[giftId] = Gift({
            recipient: recipient,
            amount: amount,
            redeemed: false
        });

        emit GiftCreated(giftId, msg.sender, recipient, amount);

        SafeTransferLib.safeTransferFrom(
            address(token),
            msg.sender,
            address(this),
            amount
        );
    }

    /// @notice Redeem a gifted token
    /// @param giftId The ID of the gift to redeem
    /// @custom:throws GiftNotFound if the gift does not exist
    /// @custom:throws NotVerified if the recipient is not verified
    /// @custom:throws AlreadyRedeemed if the gift has already been redeemed
    function redeem(uint256 giftId) public {
        Gift storage gift = getGift[giftId];

        require(!gift.redeemed, AlreadyRedeemed());
        require(gift.recipient != address(0), GiftNotFound());
        require(
            addressBook.addressVerifiedUntil(gift.recipient) >= block.timestamp,
            NotVerified()
        );

        gift.redeemed = true;

        emit GiftRedeemed(giftId, gift.recipient, gift.amount);

        SafeTransferLib.safeTransferFrom(
            address(token),
            address(this),
            gift.recipient,
            gift.amount
        );
    }
}
