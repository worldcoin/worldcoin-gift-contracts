// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IAddressBook} from "../interfaces/IAddressBook.sol";
import {MockAddressBook} from "./mocks/MockAddressBook.sol";
import {WorldCampaignManager} from "../WorldCampaignManager.sol";

contract WorldCampaignManagerTest is Test {
    MockToken public token;
    MockAddressBook public addressBook;
    WorldCampaignManager public campaignManager;

    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        token = new MockToken();
        addressBook = new MockAddressBook();
        campaignManager = new WorldCampaignManager(addressBook);

        token.mint(address(this), 100 ether);

        token.approve(address(campaignManager), type(uint256).max);

        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
        vm.label(address(token), "Mock Token");
        vm.label(address(this), "Test Contract");
        vm.label(address(campaignManager), "World Campaign Manager");
    }

    function testConstructorValidatesArguments() public {
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector);
        new WorldCampaignManager(IAddressBook(address(0)));

        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.WorldCampaignManagerInitialized(address(addressBook));
        WorldCampaignManager manager = new WorldCampaignManager(addressBook);
        assertEq(address(manager.addressBook()), address(addressBook));
    }

    function testCanCreateCampaign(uint256 _lowerBound, uint256 _upperBound, uint256 _seed) public {
        vm.assume(_lowerBound < _upperBound);

        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.CampaignCreated(1);

        uint256 campaignId = campaignManager.createCampaign(
            token, address(this), block.timestamp + 10 days, _lowerBound, _upperBound, _seed
        );

        (
            address tokenAddress,
            address fundsOrigin,
            uint256 endTime,
            bool wasEndedEarly,
            uint256 lowerBound,
            uint256 upperBound,
            uint256 randomnessSeed
        ) = campaignManager.getCampaign(campaignId);

        assertEq(wasEndedEarly, false);
        assertEq(randomnessSeed, _seed);
        assertEq(lowerBound, _lowerBound);
        assertEq(upperBound, _upperBound);
        assertEq(fundsOrigin, address(this));
        assertEq(tokenAddress, address(token));
        assertEq(endTime, block.timestamp + 10 days);
    }

    function testCampaignCreationValidatesParameters() public {
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Token address zero
        campaignManager.createCampaign(IERC20(address(0)), address(this), block.timestamp + 10 days, 1, 100, 42);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Funds origin address zero
        campaignManager.createCampaign(token, address(0), block.timestamp + 10 days, 1, 100, 42);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // End timestamp in the past
        campaignManager.createCampaign(token, address(this), block.timestamp - 1 days, 1, 100, 42);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Upper bound must be greater than lower bound
        campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 100, 50, 42);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Funds must be approved
        campaignManager.createCampaign(token, user1, block.timestamp + 10 days, 1, 100, 42);
    }

    function testOnlyOwnerCanCreateCampaign() public {
        vm.prank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1, 100, 42);
    }

    function testCanSponsor() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        assertTrue(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.Sponsored(campaignId, user1, user2);

        campaignManager.sponsor(campaignId, user2);

        assertFalse(campaignManager.canSponsor(campaignId, user1, user2));
        assertEq(campaignManager.getSponsoredRecipient(campaignId, user1), user2);
        assertEq(
            uint8(campaignManager.getClaimStatus(campaignId, user2)), uint8(WorldCampaignManager.ClaimStatus.CanClaim)
        );
    }

    function testCanOnlySponsorOnce(address randomUser) public {
        vm.assume(randomUser != user1 && randomUser != user2 && randomUser != address(0));

        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);
        addressBook.setVerification(randomUser, block.timestamp + 1000);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        assertTrue(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        assertFalse(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.AlreadyParticipated.selector);
        campaignManager.sponsor(campaignId, randomUser);
    }

    function testSponsoringRequiresEveryoneInvolvedToBeVerified() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        // user2 is not verified

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        assertFalse(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.NotVerified.selector);
        campaignManager.sponsor(campaignId, user2);

        assertFalse(campaignManager.canSponsor(campaignId, user2, user1));

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.NotVerified.selector);
        campaignManager.sponsor(campaignId, user1);
    }

    function testSponsoringFailsWhenCampaignDoesNotExist() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        assertFalse(campaignManager.canSponsor(999, user1, user2));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.sponsor(999, user2);
    }

    function testCannotSponsorZeroAddress() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(address(0), block.timestamp + 1000);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        assertFalse(campaignManager.canSponsor(campaignId, user1, address(0)));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector);
        campaignManager.sponsor(campaignId, address(0));
    }

    function testCannotSponsorAfterCampaignEnds() public {
        addressBook.setVerification(user1, block.timestamp + 10 days);
        addressBook.setVerification(user2, block.timestamp + 10 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 1 days, 1 ether, 10 ether, 100);

        vm.warp(block.timestamp + 2 days);

        assertFalse(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.sponsor(campaignId, user2);
    }

    function testCannotSponsorSelf() public {
        addressBook.setVerification(user1, block.timestamp + 1000);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        assertFalse(campaignManager.canSponsor(campaignId, user1, user1));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CannotSponsorSelf.selector);
        campaignManager.sponsor(campaignId, user1);
    }

    function testCannotSponsorUserThatHasAlreadyBeenSponsored(address someUser) public {
        vm.assume(someUser != user1 && someUser != user2 && someUser != address(0));

        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(someUser, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, someUser);

        assertFalse(campaignManager.canSponsor(campaignId, user1, someUser));
        assertFalse(campaignManager.canSponsor(campaignId, user2, someUser));

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.AlreadyParticipated.selector);
        campaignManager.sponsor(campaignId, someUser);
    }

    function testCannotSponsorUserThatAlreadyClaimed(address randomUser) public {
        vm.assume(randomUser != user1 && randomUser != user2 && randomUser != address(0));

        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(randomUser, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, randomUser);

        vm.prank(randomUser);
        campaignManager.claim(campaignId, user1);

        assertFalse(campaignManager.canSponsor(campaignId, user1, randomUser));

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.AlreadyParticipated.selector);
        campaignManager.sponsor(campaignId, randomUser);
    }

    function testCanClaim() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.Claimed(campaignId, user2, 6_130_755_916_212_758_706);

        campaignManager.claim(campaignId, user1);

        assertEq(token.balanceOf(user2), 6_130_755_916_212_758_706);
        assertEq(
            uint8(campaignManager.getClaimStatus(campaignId, user2)),
            uint8(WorldCampaignManager.ClaimStatus.AlreadyClaimed)
        );
        assertEq(token.balanceOf(address(this)), 100 ether - 6_130_755_916_212_758_706);
    }

    function testClaimRandomness(uint256 seed, uint256 lowerBound, uint256 upperBound) public {
        vm.assume(lowerBound < upperBound);

        if (upperBound > 100 ether) {
            token.mint(address(this), upperBound - 100 ether);
        }

        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, address(this), block.timestamp + 10 days, lowerBound, upperBound, seed
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.claim(campaignId, user1);

        uint256 rewardAmount = token.balanceOf(user2);

        assertTrue(rewardAmount >= lowerBound && rewardAmount < upperBound);
    }

    function testCampaignWithExactAmountRewards() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 5 ether, 5 ether, 42);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.claim(campaignId, user1);

        uint256 rewardAmount = token.balanceOf(user2);

        assertEq(rewardAmount, 5 ether);
    }

    function testCannotClaimNonExistentCampaign(address anyAddress) public {
        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.claim(999, anyAddress);
    }

    function testCannotClaimWithInvalidSponsor(address anyAddress) public {
        vm.assume(anyAddress != user1);
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector);
        campaignManager.claim(campaignId, anyAddress);
    }

    function testCannotClaimIfNotSponsored(address anyAddress) public {
        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.NotSponsored.selector);
        campaignManager.claim(campaignId, anyAddress);
    }

    function testCannotClaimAfterCampaignEnds() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 1 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.claim(campaignId, user1);
    }

    function testCannotClaimTwice() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.claim(campaignId, user1);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.NotSponsored.selector);
        campaignManager.claim(campaignId, user1);
    }

    function testCanEndCampaignEarly() public {
        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        campaignManager.endCampaignEarly(campaignId);

        (,,, bool wasEndedEarly,,,) = campaignManager.getCampaign(campaignId);

        assertTrue(wasEndedEarly);
    }

    function testOnlyOwnerCanEndCampaignEarly() public {
        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        campaignManager.endCampaignEarly(campaignId);
    }

    function testCannotEndNonExistentCampaignEarly() public {
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.endCampaignEarly(999);
    }

    function testCannotEndAlreadyEndedCampaignEarly() public {
        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        campaignManager.endCampaignEarly(campaignId);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.endCampaignEarly(campaignId);

        uint256 secondCampaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.warp(block.timestamp + 11 days);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.endCampaignEarly(secondCampaignId);
    }

    function testCannotSponsorOnEndedEarlyCampaign() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        campaignManager.endCampaignEarly(campaignId);

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.sponsor(campaignId, user2);
    }

    function testCanStillClaimOnEndedEarlyCampaign() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId =
            campaignManager.createCampaign(token, address(this), block.timestamp + 10 days, 1 ether, 10 ether, 100);

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        campaignManager.endCampaignEarly(campaignId);

        vm.prank(user2);
        campaignManager.claim(campaignId, user1);

        assertEq(
            uint8(campaignManager.getClaimStatus(campaignId, user2)),
            uint8(WorldCampaignManager.ClaimStatus.AlreadyClaimed)
        );
    }
}
