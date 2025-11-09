// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockAddressBook} from "./mocks/MockAddressBook.sol";
import {
    IERC20,
    WorldGiftManager,
    SafeTransferLib
} from "../src/WorldGiftManager.sol";

contract WorldGiftManagerTest is Test {
    MockToken public token;
    MockAddressBook public addressBook;
    WorldGiftManager public giftManager;

    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        token = new MockToken();
        addressBook = new MockAddressBook();
        giftManager = new WorldGiftManager(IERC20(address(token)), addressBook);

        token.mint(address(this), 100 ether);
        token.approve(address(giftManager), type(uint256).max);

        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
        vm.label(address(token), "Mock Token");
        vm.label(address(this), "Test Contract");
        vm.label(address(addressBook), "Mock Address Book");
        vm.label(address(giftManager), "World Gift Manager");
    }

    function testConstructorVerifiesArguments() public {
        // token address cannot be zero
        vm.expectRevert(WorldGiftManager.InvalidConfiguration.selector);
        new WorldGiftManager(IERC20(address(0x0)), addressBook);

        // address book address cannot be zero
        vm.expectRevert(WorldGiftManager.InvalidConfiguration.selector);
        new WorldGiftManager(
            IERC20(address(token)),
            MockAddressBook(address(0x0))
        );

        // constructor emits an eventL
        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.WorldGiftManagerInitialized(
            IERC20(address(token)),
            addressBook
        );

        WorldGiftManager newGiftManager = new WorldGiftManager(
            IERC20(address(token)),
            addressBook
        );

        assertEq(newGiftManager.owner(), address(this));
    }

    function testCanGift() public {
        vm.expectEmit(true, true, true, true);
        emit WorldGiftManager.GiftCreated(1, address(this), user1, 1 ether);

        uint256 giftId = giftManager.gift(user1, 1 ether);
        assertEq(giftId, 1);

        (address recipient, uint256 amount, bool redeemed) = giftManager
            .getGift(giftId);

        assertEq(recipient, user1);
        assertEq(amount, 1 ether);
        assertEq(redeemed, false);

        assertEq(token.balanceOf(address(this)), 99 ether);
        assertEq(token.balanceOf(address(giftManager)), 1 ether);
    }

    function testGiftingFailsWhenInsufficientBalance() public {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);

        vm.prank(user1);
        giftManager.gift(user2, 1 ether);
    }

    function testCannotGiftZeroAmount() public {
        vm.expectRevert(WorldGiftManager.InvalidAmount.selector);
        giftManager.gift(user1, 0);
    }

    function testCannotGiftToZeroAddress() public {
        vm.expectRevert(WorldGiftManager.InvalidRecipient.selector);
        giftManager.gift(address(0), 1 ether);
    }
}
