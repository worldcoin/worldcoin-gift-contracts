// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {WorldGiftManager} from "../WorldGiftManager.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract WorldGiftManagerTest is Test {
    MockToken public token;
    MockToken public secondToken;
    WorldGiftManager public giftManager;

    address user1;
    address user2;
    uint256 user1Sig;
    uint256 user2Sig;

    function setUp() public {
        token = new MockToken();
        secondToken = new MockToken();
        (user1, user1Sig) = makeAddrAndKey("User 1");
        (user2, user2Sig) = makeAddrAndKey("User 2");
        giftManager = new WorldGiftManager();

        token.mint(address(this), 100 ether);
        secondToken.mint(address(this), 100 ether);

        token.approve(address(giftManager), type(uint256).max);
        secondToken.approve(address(giftManager), type(uint256).max);

        giftManager.setTokenAllowed(address(token), true);

        vm.label(address(token), "Mock Token");
        vm.label(address(this), "Test Contract");
        vm.label(address(secondToken), "Second Mock Token");
        vm.label(address(giftManager), "World Gift Manager");
    }

    function testConstructorEmitsEvent() public {
        // constructor emits an event
        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.WorldGiftManagerInitialized();

        WorldGiftManager newGiftManager = new WorldGiftManager();

        assertEq(newGiftManager.owner(), address(this));
    }

    function testCanGift(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftCreated(1, address(token), address(this), recipient, amount);

        uint256 giftId = giftManager.gift(token, recipient, amount);
        assertEq(giftId, 1);

        (
            address sender,
            address giftRecipient,
            address storedToken,
            uint256 giftAmount,
            uint256 createdAt,
            bool redeemed,
            bool cancelled
        ) = giftManager.getGift(giftId);

        assertEq(giftAmount, amount);
        assertEq(redeemed, false);
        assertEq(cancelled, false);
        assertEq(sender, address(this));
        assertEq(giftRecipient, recipient);
        assertEq(createdAt, block.timestamp);
        assertEq(storedToken, address(token));

        assertEq(token.balanceOf(address(this)), 100 ether - amount);
        assertEq(token.balanceOf(address(giftManager)), amount);
    }

    function testCanGiftWithSig(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        vm.startPrank(user1);
        token.mint(user1, 100 ether);
        token.approve(address(giftManager), amount);
        vm.stopPrank();

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(token), recipient, amount, giftManager.nextNonceForUser(user1));

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftCreated(1, address(token), user1, recipient, amount);

        uint256 giftId = giftManager.giftWithSig(token, user1, recipient, amount, signature);
        assertEq(giftId, 1);
        assertEq(giftManager.nextNonceForUser(user1), 1);

        (
            address sender,
            address giftRecipient,
            address storedToken,
            uint256 giftAmount,
            uint256 createdAt,
            bool redeemed,
            bool cancelled
        ) = giftManager.getGift(giftId);

        assertEq(redeemed, false);
        assertEq(cancelled, false);
        assertEq(sender, user1);
        assertEq(giftAmount, amount);
        assertEq(giftRecipient, recipient);
        assertEq(createdAt, block.timestamp);
        assertEq(storedToken, address(token));

        assertEq(token.balanceOf(user1), 100 ether - amount);
        assertEq(token.balanceOf(address(giftManager)), amount);
    }

    function testGiftingFailsWhenInsufficientBalance(uint256 amount) public {
        vm.assume(amount > 0);

        vm.prank(user1);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        giftManager.gift(token, user1, 1 ether);

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(token), user2, 1 ether, giftManager.nextNonceForUser(user1));

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        giftManager.giftWithSig(token, user1, user2, 1 ether, signature);
    }

    function testCannotGiftWhenTokenNotAllowed(address tokenToGift) public {
        vm.assume(tokenToGift != address(token));

        vm.expectRevert(WorldGiftManager.TokenNotAllowed.selector);
        giftManager.gift(IERC20(tokenToGift), user1, 1 ether);

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(tokenToGift), user2, 1 ether, giftManager.nextNonceForUser(user1));

        vm.expectRevert(WorldGiftManager.TokenNotAllowed.selector);
        giftManager.giftWithSig(IERC20(tokenToGift), user1, user2, 1 ether, signature);
    }

    function testCannotGiftZeroAmount() public {
        vm.expectRevert(WorldGiftManager.InvalidAmount.selector);
        giftManager.gift(token, user1, 0);

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(token), user2, 0, giftManager.nextNonceForUser(user1));

        vm.expectRevert(WorldGiftManager.InvalidAmount.selector);
        giftManager.giftWithSig(IERC20(token), user1, user2, 0, signature);
    }

    function testCannotGiftToZeroAddress(uint256 amount) public {
        vm.assume(amount > 0);

        vm.expectRevert(WorldGiftManager.InvalidRecipient.selector);
        giftManager.gift(token, address(0), amount);

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(token), address(0), amount, giftManager.nextNonceForUser(user1));

        vm.expectRevert(WorldGiftManager.InvalidRecipient.selector);
        giftManager.giftWithSig(IERC20(token), user1, address(0), amount, signature);
    }

    function testCannotGiftWithInvalidSignature(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(0x1234)); // used for mismatched recipient below

        // Invalid signature: signed by different user
        bytes memory invalidSignature =
            _generateGiftSignature(user2Sig, address(token), recipient, amount, giftManager.nextNonceForUser(user2));

        vm.expectRevert(WorldGiftManager.InvalidSignature.selector);
        giftManager.giftWithSig(token, user1, recipient, amount, invalidSignature);

        // Invalid signature: signed over different token
        invalidSignature =
            _generateGiftSignature(user2Sig, address(0x1), recipient, amount, giftManager.nextNonceForUser(user2));

        vm.expectRevert(WorldGiftManager.InvalidSignature.selector);
        giftManager.giftWithSig(token, user2, recipient, amount, invalidSignature);

        // Invalid signature: signed over different amount
        invalidSignature =
            _generateGiftSignature(user2Sig, address(token), recipient, amount, giftManager.nextNonceForUser(user2));

        vm.expectRevert(WorldGiftManager.InvalidSignature.selector);
        giftManager.giftWithSig(token, user2, recipient, amount + 1, invalidSignature);

        // Invalid signature: signed over different recipient
        invalidSignature =
            _generateGiftSignature(user2Sig, address(token), recipient, amount, giftManager.nextNonceForUser(user2));

        vm.expectRevert(WorldGiftManager.InvalidSignature.selector);
        giftManager.giftWithSig(token, user2, address(0x1234), amount, invalidSignature);

        // Invalid signature: signed over different nonce
        invalidSignature = _generateGiftSignature(user2Sig, address(token), recipient, amount, 1);
        vm.expectRevert(WorldGiftManager.InvalidSignature.selector);
        giftManager.giftWithSig(token, user2, recipient, amount, invalidSignature);
    }

    function testCannotReuseNonceInGiftWithSig(uint256 amount, address recipient) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0 && amount <= 100 ether);

        vm.startPrank(user1);
        token.mint(user1, 100 ether);
        token.approve(address(giftManager), amount * 2);
        vm.stopPrank();

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(token), recipient, amount, giftManager.nextNonceForUser(user1));

        uint256 giftId = giftManager.giftWithSig(token, user1, recipient, amount, signature);
        assertEq(giftId, 1);

        // Reusing the same nonce should fail
        vm.expectRevert(WorldGiftManager.InvalidSignature.selector);
        giftManager.giftWithSig(token, user1, recipient, amount, signature);
    }

    function testCanRedeemGift(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);

        uint256 giftId = giftManager.gift(token, user1, amount);

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftRedeemed(giftId, user1, amount);

        vm.prank(user1);
        giftManager.redeem(giftId);

        (,,,,, bool redeemed,) = giftManager.getGift(giftId);
        assertEq(redeemed, true);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(address(giftManager)), 0);
    }

    function testCanRedeemGiftCreatedWithSig(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);

        vm.startPrank(user1);
        token.mint(user1, amount);
        token.approve(address(giftManager), amount);
        vm.stopPrank();

        bytes memory signature =
            _generateGiftSignature(user1Sig, address(token), user2, amount, giftManager.nextNonceForUser(user1));
        uint256 giftId = giftManager.giftWithSig(token, user1, user2, amount, signature);

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftRedeemed(giftId, user2, amount);

        vm.prank(user2);
        giftManager.redeem(giftId);

        (,,,,, bool redeemed,) = giftManager.getGift(giftId);
        assertEq(redeemed, true);

        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(address(giftManager)), 0);
    }

    function testCannotRedeemCancelledGift(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        uint256 giftId = giftManager.gift(token, recipient, amount);

        giftManager.cancel(giftId);

        vm.prank(user1);
        vm.expectRevert(WorldGiftManager.GiftHasBeenCancelled.selector);
        giftManager.redeem(giftId);
    }

    function testCannotRedeemGiftTwice(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);

        uint256 giftId = giftManager.gift(token, user1, amount);

        vm.prank(user1);
        giftManager.redeem(giftId);

        vm.expectRevert(WorldGiftManager.AlreadyRedeemed.selector);
        vm.prank(user1);
        giftManager.redeem(giftId);
    }

    function testCannotRedeemGiftForAnotherUser(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);

        uint256 giftId = giftManager.gift(token, user1, amount);

        vm.prank(user2);
        vm.expectRevert(WorldGiftManager.NotRecipient.selector);
        giftManager.redeem(giftId);
    }

    function testCannotRedeemNonexistentGift() public {
        vm.expectRevert(WorldGiftManager.GiftNotFound.selector);
        giftManager.redeem(999);
    }

    function testCanCancelGift(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        uint256 giftId = giftManager.gift(token, recipient, amount);

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftCancelled(giftId);

        giftManager.cancel(giftId);

        (,,,,, bool redeemed, bool cancelled) = giftManager.getGift(giftId);
        assertEq(redeemed, false);
        assertEq(cancelled, true);

        assertEq(token.balanceOf(address(this)), 100 ether);
        assertEq(token.balanceOf(address(giftManager)), 0);
    }

    function testCannotCancelGiftAfterRedeemed(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        uint256 giftId = giftManager.gift(token, recipient, amount);

        vm.prank(recipient);
        giftManager.redeem(giftId);

        vm.expectRevert(WorldGiftManager.AlreadyRedeemed.selector);
        giftManager.cancel(giftId);
    }

    function testCannotCancelAlreadyCancelledGift(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        uint256 giftId = giftManager.gift(token, recipient, amount);

        giftManager.cancel(giftId);

        vm.expectRevert(WorldGiftManager.GiftHasBeenCancelled.selector);
        giftManager.cancel(giftId);
    }

    function testCannotCancelNonexistentGift() public {
        vm.expectRevert(WorldGiftManager.GiftNotFound.selector);
        giftManager.cancel(999);
    }

    function testCannotCancelSomeoneElsesGiftBeforeCancelablePeriod(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        uint256 giftId = giftManager.gift(token, recipient, amount);

        vm.prank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        giftManager.cancel(giftId);
    }

    function testCanCancelSomeoneElsesGiftAfterCancelablePeriod(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        uint256 giftId = giftManager.gift(token, recipient, amount);

        vm.warp(block.timestamp + giftManager.GIFT_CANCELABLE_AFTER() + 1);

        vm.prank(user1);
        giftManager.cancel(giftId);

        (,,,,, bool redeemed, bool cancelled) = giftManager.getGift(giftId);
        assertEq(redeemed, false);
        assertEq(cancelled, true);

        assertEq(token.balanceOf(address(this)), 100 ether);
        assertEq(token.balanceOf(address(giftManager)), 0);
    }

    function testOnlyAdminCanSetTokenAllowed(address caller) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        giftManager.setTokenAllowed(address(secondToken), true);
    }

    function testCanSetTokenAllowed() public {
        assertEq(giftManager.isTokenAllowed(address(token)), true);
        assertEq(giftManager.isTokenAllowed(address(secondToken)), false);

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.TokenAllowlistUpdated(address(secondToken), true);

        giftManager.setTokenAllowed(address(secondToken), true);
        assertEq(giftManager.isTokenAllowed(address(secondToken)), true);

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.TokenAllowlistUpdated(address(secondToken), false);

        giftManager.setTokenAllowed(address(secondToken), false);
        assertEq(giftManager.isTokenAllowed(address(secondToken)), false);
    }

    /// @dev Helper function to generate gift signature
    /// @param privateKey The user's private key
    /// @param amount The amount of tokens to gift
    function _generateGiftSignature(uint256 privateKey, address token, address recipient, uint256 amount, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("Gift(address token,address recipient,uint256 amount,uint256 nonce)"),
                        token,
                        recipient,
                        amount,
                        nonce
                    )
                )
            )
        );

        return abi.encodePacked(r, s, v);
    }

    /// @dev Helper function to hash EIP712 typed data for the gift signature
    /// @param structHash The hash of the Gift struct
    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        /// forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encodePacked("\x19\x01", giftManager.DOMAIN_SEPARATOR(), structHash));
    }
}
