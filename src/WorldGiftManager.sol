// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {EIP712} from "solady/utils/EIP712.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IAddressBook} from "./interfaces/IAddressBook.sol";
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

    /// @notice Thrown when an unverified recipient attempts to redeem a gift
    error NotVerified();

    /// @notice Thrown when trying to redeem a non-existent gift
    error GiftNotFound();

    /// @notice Thrown when trying to redeem a gift that has already been redeemed
    error AlreadyRedeemed();

    /// @notice Thrown when trying to send a gift with an invalid recipient
    error InvalidRecipient();

    /// @notice Thrown when trying to send a gift with an invalid amount
    error InvalidAmount();

    /// @notice Thrown when trying to send a gift with an unallowed token
    error TokenNotAllowed();

    /// @notice Thrown when trying to send a gift with an invalid nonce
    error InvalidNonce();

    /// @notice Thrown when trying to send a gift with an invalid signature
    error InvalidSignature();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the contract is initialized
    /// @param addressBook The address of the address book contract
    event WorldGiftManagerInitialized(IAddressBook indexed addressBook);

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

    /// @notice Emitted whenever a token allowlist entry is updated
    /// @param token The ERC20 token whose status changed
    /// @param allowed Whether the token is now allowed
    event TokenAllowlistUpdated(address indexed token, bool allowed);

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

    /// @notice Whether a withdrawal nonce has been used
    mapping(uint256 => bool) public isNonceConsumed;

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONSTRUCTOR                              ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Create a new WorldGiftManager contract
    /// @param _addressBook The AddressBook contract for verification checks
    constructor(IAddressBook _addressBook) {
        require(address(_addressBook) != address(0), InvalidConfiguration());

        addressBook = _addressBook;

        _initializeOwner(msg.sender);

        emit WorldGiftManagerInitialized(addressBook);
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
    /// @custom:throws InvalidRecipient if the recipient is the sender or zero address
    /// @return giftId The ID of the created gift
    function gift(IERC20 token, address recipient, uint256 amount) external returns (uint256) {
        return _gift(token, msg.sender, recipient, amount);
    }

    /// @notice Gift tokens to a recipient using a signed message
    /// @param token The ERC20 token to gift
    /// @param sender The address of the gift sender
    /// @param recipient The address of the gift recipient
    /// @param amount The amount of tokens to gift
    /// @param nonce A unique nonce for this gift
    /// @param signature The sender's signature over the gift parameters
    /// @custom:throws InvalidAmount if the amount is zero
    /// @custom:throws InvalidSignature if the signature is invalid
    /// @custom:throws InvalidNonce if the nonce has already been used
    /// @custom:throws TokenNotAllowed if the token is not allowed for gifting
    /// @custom:throws InvalidRecipient if the recipient is the sender or zero address
    /// @return giftId The ID of the created gift
    function giftWithSig(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external returns (uint256) {
        require(!isNonceConsumed[nonce], InvalidNonce());

        bool isSigValid = SignatureCheckerLib.isValidSignatureNow(
            sender,
            _hashTypedData(
                keccak256(
                    abi.encode(
                        keccak256("Gift(address token,address recipient,uint256 amount,uint256 nonce)"),
                        address(token),
                        recipient,
                        amount,
                        nonce
                    )
                )
            ),
            signature
        );

        require(isSigValid, InvalidSignature());

        isNonceConsumed[nonce] = true;

        return _gift(token, sender, recipient, amount);
    }

    /// @notice Redeem a gifted token
    /// @param giftId The ID of the gift to redeem
    /// @custom:throws GiftNotFound if the gift does not exist
    /// @custom:throws NotVerified if the recipient is not verified
    /// @custom:throws AlreadyRedeemed if the gift has already been redeemed
    function redeem(uint256 giftId) external {
        Gift storage gift = getGift[giftId];

        require(!gift.redeemed, AlreadyRedeemed());
        require(gift.recipient != address(0), GiftNotFound());
        require(addressBook.addressVerifiedUntil(gift.recipient) >= block.timestamp, NotVerified());

        gift.redeemed = true;

        emit GiftRedeemed(giftId, gift.recipient, gift.amount);

        SafeTransferLib.safeTransferFrom(gift.token, address(this), gift.recipient, gift.amount);
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
    /// @custom:throws InvalidRecipient if the recipient is the sender or zero address
    /// @return giftId The ID of the created gift
    function _gift(IERC20 token, address from, address to, uint256 amount) internal returns (uint256 giftId) {
        require(amount > 0, InvalidAmount());
        require(to != address(0), InvalidRecipient());
        require(isTokenAllowed[address(token)], TokenNotAllowed());

        unchecked {
            giftId = nextGiftId++;
        }

        getGift[giftId] = Gift({token: address(token), recipient: to, amount: amount, redeemed: false});

        emit GiftCreated(giftId, address(token), from, to, amount);

        SafeTransferLib.safeTransferFrom(address(token), from, address(this), amount);
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "WorldGiftManager";
        version = "1.0";
    }
}
