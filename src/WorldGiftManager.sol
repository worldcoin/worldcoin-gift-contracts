// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {EIP712} from "solady/utils/EIP712.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @title World Gift Manager
/// @author Miguel Piedrafita
/// @notice Allows World App users to send and redeem token gifts
contract WorldGiftManager is Ownable, EIP712 {
    ///////////////////////////////////////////////////////////////////////////////
    ///                                  ERRORS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when the contract is misconfigured
    error InvalidConfiguration();

    /// @notice Thrown when trying to redeem or cancel a non-existent gift
    error GiftNotFound();

    /// @notice Thrown when trying to redeem or cancel a cancelled gift
    error GiftHasBeenCancelled();

    /// @notice Thrown when trying to redeem a gift that has already been redeemed
    error AlreadyRedeemed();

    /// @notice Thrown when trying to send a gift with an invalid recipient
    error InvalidRecipient();

    /// @notice Thrown when trying to send a gift with an invalid amount
    error InvalidAmount();

    /// @notice Thrown when trying to send a gift with an unallowed token
    error TokenNotAllowed();

    /// @notice Thrown when trying to send a gift with an invalid signature
    error InvalidSignature();

    /// @notice Thrown when trying to redeem a gift meant for another user
    error NotRecipient();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the contract is initialized
    event WorldGiftManagerInitialized();

    /// @notice Emitted when a gift is created
    /// @param giftId The ID of the created gift
    /// @param token The address of the ERC20 token being gifted
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens gifted
    event GiftCreated(
        uint256 indexed giftId, address indexed token, address indexed sender, address recipient, uint256 amount
    );

    /// @notice Emitted when a gift is redeemed
    /// @param giftId The ID of the redeemed gift
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens redeemed
    event GiftRedeemed(uint256 indexed giftId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a gift is cancelled
    /// @param giftId The ID of the cancelled gift
    event GiftCancelled(uint256 indexed giftId);

    /// @notice Emitted whenever a token allowlist entry is updated
    /// @param token The ERC20 token whose status changed
    /// @param allowed Whether the token is now allowed
    event TokenAllowlistUpdated(address indexed token, bool allowed);

    ///////////////////////////////////////////////////////////////////////////////
    ///                            TYPE DECLARATIONS                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Represents a gift of tokens
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param token The address of the ERC20 token being gifted
    /// @param amount The amount of tokens gifted
    /// @param createdAt The timestamp when the gift was created
    /// @param redeemed Whether the gift has been redeemed
    /// @param cancelled Whether the gift has been cancelled
    struct Gift {
        address sender;
        address recipient;
        address token;
        uint256 amount;
        uint256 createdAt;
        bool redeemed;
        bool cancelled;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              CONFIG STORAGE                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice The duration after which anyone can send a gift back to the sender
    /// @dev Note that the sender can always cancel the gift at any time before redemption.
    uint256 public constant GIFT_CANCELABLE_AFTER = 7 days;

    /// @notice The next gift ID to be assigned
    uint256 private nextGiftId = 1;

    /// @notice A mapping of gift IDs to Gift structs
    mapping(uint256 => Gift) public getGift;

    /// @notice A mapping of allowed ERC20 tokens
    mapping(address => bool) public isTokenAllowed;

    /// @notice Whether a withdrawal nonce has been used
    mapping(address => uint256) public nextNonceForUser;

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONSTRUCTOR                              ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Create a new WorldGiftManager contract
    constructor() {
        _initializeOwner(msg.sender);

        emit WorldGiftManagerInitialized();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               MAIN LOGIC                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Gift tokens to a recipient
    /// @param token The ERC20 token to gift
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens to gift
    /// @custom:throws InvalidAmount if the amount is zero
    /// @custom:throws TokenNotAllowed if the token is not allowed for gifting
    /// @custom:throws InvalidRecipient if the recipient is the zero address
    /// @return giftId The ID of the created gift
    function gift(IERC20 token, address recipient, uint256 amount) external returns (uint256) {
        return _gift(token, msg.sender, recipient, amount);
    }

    /// @notice Gift tokens to a recipient using a signed message
    /// @param token The ERC20 token to gift
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens to gift
    /// @param signature The sender's signature over the gift parameters
    /// @custom:throws InvalidAmount if the amount is zero
    /// @custom:throws InvalidSignature if the signature is invalid
    /// @custom:throws TokenNotAllowed if the token is not allowed for gifting
    /// @custom:throws InvalidRecipient if the recipient is the zero address
    /// @return giftId The ID of the created gift
    function giftWithSig(IERC20 token, address sender, address recipient, uint256 amount, bytes calldata signature)
        external
        returns (uint256)
    {
        bool isSigValid = SignatureCheckerLib.isValidSignatureNow(
            sender,
            _hashTypedData(
                keccak256(
                    abi.encode(
                        keccak256("Gift(address token,address recipient,uint256 amount,uint256 nonce)"),
                        address(token),
                        recipient,
                        amount,
                        nextNonceForUser[sender]
                    )
                )
            ),
            signature
        );

        require(isSigValid, InvalidSignature());

        unchecked {
            nextNonceForUser[sender]++;
        }

        return _gift(token, sender, recipient, amount);
    }

    /// @notice Redeem a gifted token
    /// @param giftId The ID of the gift to redeem
    /// @custom:throws GiftNotFound if the gift does not exist
    /// @custom:throws AlreadyRedeemed if the gift has already been redeemed
    function redeem(uint256 giftId) external {
        Gift storage gift = getGift[giftId];

        require(!gift.redeemed, AlreadyRedeemed());
        require(!gift.cancelled, GiftHasBeenCancelled());
        require(gift.recipient != address(0), GiftNotFound());
        require(gift.recipient == msg.sender, NotRecipient());

        gift.redeemed = true;

        emit GiftRedeemed(giftId, gift.recipient, gift.amount);

        SafeTransferLib.safeTransfer(gift.token, gift.recipient, gift.amount);
    }

    function cancel(uint256 giftId) external {
        Gift storage gift = getGift[giftId];

        require(!gift.redeemed, AlreadyRedeemed());
        require(!gift.cancelled, GiftHasBeenCancelled());
        require(gift.recipient != address(0), GiftNotFound());
        require(gift.sender == msg.sender || block.timestamp >= gift.createdAt + GIFT_CANCELABLE_AFTER, Unauthorized());

        gift.cancelled = true;

        emit GiftCancelled(giftId);

        SafeTransferLib.safeTransfer(gift.token, gift.sender, gift.amount);
    }

    /// @dev The EIP-712 domain separator
    /// @return separator The EIP-712 domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32 separator) {
        separator = _domainSeparator();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONFIG LOGIC                             ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Set whether an ERC20 token is allowed for gifting
    /// @param token The address of the ERC20 token
    /// @param allowed Whether the token is allowed
    function setTokenAllowed(address token, bool allowed) public onlyOwner {
        isTokenAllowed[token] = allowed;

        emit TokenAllowlistUpdated(token, allowed);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              INTERNAL LOGIC                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @dev Gift tokens to a recipient
    /// @param token The ERC20 token to gift
    /// @param from The address of the gift sender
    /// @param to The address of the gift recipient
    /// @param amount The amount of tokens to gift
    /// @custom:throws InvalidAmount if the amount is zero
    /// @custom:throws TokenNotAllowed if the token is not allowed for gifting
    /// @custom:throws InvalidRecipient if the recipient is the zero address
    /// @return giftId The ID of the created gift
    function _gift(IERC20 token, address from, address to, uint256 amount) internal returns (uint256 giftId) {
        require(amount > 0, InvalidAmount());
        require(to != address(0), InvalidRecipient());
        require(isTokenAllowed[address(token)], TokenNotAllowed());

        unchecked {
            giftId = nextGiftId++;
        }

        getGift[giftId] = Gift({
            sender: from,
            recipient: to,
            token: address(token),
            amount: amount,
            createdAt: block.timestamp,
            redeemed: false,
            cancelled: false
        });

        emit GiftCreated(giftId, address(token), from, to, amount);

        SafeTransferLib.safeTransferFrom2(address(token), from, address(this), amount);
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "WorldGiftManager";
        version = "1.0";
    }
}
