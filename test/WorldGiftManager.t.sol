// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MockAddressBook} from "./mocks/MockAddressBook.sol";
import {WorldGiftManager} from "../src/WorldGiftManager.sol";
import {IAddressBook} from "../src/interfaces/IAddressBook.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract WorldGiftManagerTest is Test {
    MockToken public token;
    MockToken public secondToken;
    MockAddressBook public addressBook;
    WorldGiftManager public giftManager;

    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        token = new MockToken();
        secondToken = new MockToken();
        addressBook = new MockAddressBook();
        giftManager = new WorldGiftManager(addressBook);

        token.mint(address(this), 100 ether);
        secondToken.mint(address(this), 100 ether);

        token.approve(address(giftManager), type(uint256).max);
        secondToken.approve(address(giftManager), type(uint256).max);

        giftManager.setTokenAllowed(address(token), true);

        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
        vm.label(address(token), "Mock Token");
        vm.label(address(this), "Test Contract");
        vm.label(address(addressBook), "Mock Address Book");
        vm.label(address(secondToken), "Second Mock Token");
        vm.label(address(giftManager), "World Gift Manager");
    }

    function testConstructorVerifiesArguments() public {
        // address book address cannot be zero
        vm.expectRevert(WorldGiftManager.InvalidConfiguration.selector);
        new WorldGiftManager(IAddressBook(address(0x0)));

        // constructor emits an event
        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.WorldGiftManagerInitialized(addressBook);

        WorldGiftManager newGiftManager = new WorldGiftManager(addressBook);

        assertEq(newGiftManager.owner(), address(this));
    }

    function testCanGift(uint256 amount, address recipient) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.assume(recipient != address(0) && recipient != address(this));

        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftCreated(1, address(token), address(this), recipient, amount);

        uint256 giftId = giftManager.gift(token, recipient, amount);
        assertEq(giftId, 1);

        (address giftRecipient, address storedToken, uint256 giftAmount, bool redeemed) = giftManager.getGift(giftId);

        assertEq(giftAmount, amount);
        assertEq(redeemed, false);
        assertEq(giftRecipient, recipient);
        assertEq(storedToken, address(token));

        assertEq(token.balanceOf(address(this)), 100 ether - amount);
        assertEq(token.balanceOf(address(giftManager)), amount);
    }

    function testGiftingFailsWhenInsufficientBalance(uint256 balance) public {
        vm.assume(balance > 0);

        vm.prank(user1);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        giftManager.gift(token, user2, 1 ether);
    }

    function testCannotGiftWhenTokenNotAllowed(address tokenToGift) public {
        vm.assume(tokenToGift != address(token));

        vm.expectRevert(WorldGiftManager.TokenNotAllowed.selector);
        giftManager.gift(IERC20(tokenToGift), user1, 1 ether);
    }

    function testCannotGiftZeroAmount() public {
        vm.expectRevert(WorldGiftManager.InvalidAmount.selector);
        giftManager.gift(token, user1, 0);
    }

    function testCannotGiftToZeroAddress(uint256 amount) public {
        vm.assume(amount > 0);

        vm.expectRevert(WorldGiftManager.InvalidRecipient.selector);
        giftManager.gift(token, address(0), amount);
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
}
