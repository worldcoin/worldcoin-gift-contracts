// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IAddressBook} from "../interfaces/IAddressBook.sol";
import {MockAddressBook} from "./mocks/MockAddressBook.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {WorldCampaignManager} from "../WorldCampaignManager.sol";

contract WorldCampaignManagerTest is Test {
    MockToken public token;
    MockAddressBook public addressBook;
    WorldCampaignManager public campaignManager;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    function setUp() public {
        token = new MockToken();
        addressBook = new MockAddressBook();
        campaignManager = new WorldCampaignManager(addressBook);

        token.mint(address(this), 100 ether);

        token.approve(address(campaignManager), type(uint256).max);

        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
        vm.label(user3, "User 3");
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

    function testCanCreateCampaign(
        uint256 _lowerBound,
        uint256 _upperBound,
        uint256 _bonusRewardThreshold,
        uint256 _bonusRewardAmount
    ) public {
        vm.assume(_lowerBound < _upperBound);
        vm.assume(_bonusRewardAmount > _upperBound);
        vm.assume(_bonusRewardThreshold > _lowerBound && _bonusRewardThreshold < _upperBound);

        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.CampaignCreated(1);

        uint256 campaignId = campaignManager.createCampaign(
            token,
            50 ether,
            block.timestamp + 10 days,
            _lowerBound,
            _upperBound,
            _bonusRewardThreshold,
            _bonusRewardAmount
        );

        (
            address tokenAddress,
            uint256 availableFunds,
            uint256 endTime,
            bool wasEndedEarly,
            uint256 lowerBound,
            uint256 upperBound,
            uint256 bonusRewardThreshold,
            uint256 bonusRewardAmount,
            uint256 randomnessSeed
        ) = campaignManager.getCampaign(campaignId);

        assertEq(wasEndedEarly, false);
        assertEq(lowerBound, _lowerBound);
        assertEq(upperBound, _upperBound);
        assertEq(availableFunds, 50 ether);
        assertEq(tokenAddress, address(token));
        assertEq(randomnessSeed, block.prevrandao);
        assertEq(endTime, block.timestamp + 10 days);
        assertEq(bonusRewardAmount, _bonusRewardAmount);
        assertEq(bonusRewardThreshold, _bonusRewardThreshold);

        assertEq(token.balanceOf(address(this)), 50 ether);
        assertEq(token.balanceOf(address(campaignManager)), 50 ether);
    }

    function testCampaignCreationValidatesParameters() public {
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Token address zero
        campaignManager.createCampaign(IERC20(address(0)), 50 ether, block.timestamp + 10 days, 1, 100, 90, 200);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // End timestamp in the past
        campaignManager.createCampaign(token, 50 ether, block.timestamp - 1 days, 1, 100, 90, 200);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Upper bound must be greater than lower bound
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 100, 50, 90, 200);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Amount must be greater than zero
        campaignManager.createCampaign(token, 0, block.timestamp + 10 days, 1, 100, 90, 200);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector); // Creator must have enough funds to fund initial deposit
        campaignManager.createCampaign(token, 200 ether, block.timestamp + 10 days, 1, 100, 90, 200);

        token.approve(address(campaignManager), 0);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector); // Creator must have approved the contract to pull funds
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 1, 100, 90, 200);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Bonus reward threshold must be less than upper bound
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 1, 100, 150, 200);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Bonus reward threshold must be more than lower bound
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 100, 200, 50, 300);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Bonus reward amount must be greater than upper bound
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 1, 100, 150, 80);

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector); // Bonus reward threshold must be lower than reward amount
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 1, 100, 90, 80);
    }

    function testOnlyOwnerCanCreateCampaign() public {
        vm.prank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        campaignManager.createCampaign(token, 50 ether, block.timestamp + 10 days, 1, 100, 90, 200);
    }

    function testCanFundCampaign() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 200 ether
        );

        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.CampaignFunded(campaignId, 25 ether);

        campaignManager.fundCampaign(campaignId, 25 ether);

        (, uint256 availableFunds,,,,,,,) = campaignManager.getCampaign(campaignId);

        assertEq(availableFunds, 75 ether);
        assertEq(token.balanceOf(address(this)), 25 ether);
        assertEq(token.balanceOf(address(campaignManager)), 75 ether);
    }

    function testCannotFundNonExistentCampaign() public {
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.fundCampaign(999, 10 ether);
    }

    function testCannotFundEndedCampaign() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.fundCampaign(campaignId, 10 ether);
    }

    function testCannotFundFreshlyEndedCampaign() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.fundCampaign(campaignId, 10 ether);
    }

    function testCannotFundWithZeroAmount() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector);
        campaignManager.fundCampaign(campaignId, 0);
    }

    function testCanWithdrawUnclaimedFunds() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.ExcessFundsWithdrawn(campaignId, 50 ether);

        campaignManager.withdrawUnclaimedFunds(campaignId);

        assertEq(token.balanceOf(address(this)), 100 ether);
        assertEq(token.balanceOf(address(campaignManager)), 0);
    }

    function testOnlyOwnerCanWithdrawUnclaimedFunds(address anyUser) public {
        vm.assume(anyUser != address(this));

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 2 days);

        vm.prank(anyUser);
        vm.expectRevert(Ownable.Unauthorized.selector);
        campaignManager.withdrawUnclaimedFunds(campaignId);
    }

    function testCannotWithdrawFromNonExistentCampaign() public {
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.withdrawUnclaimedFunds(999);
    }

    function testCannotWithdrawFromActiveCampaign() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.expectRevert(WorldCampaignManager.CampaignActive.selector);
        campaignManager.withdrawUnclaimedFunds(campaignId);
    }

    function testCanSponsor() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        assertTrue(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.Sponsored(campaignId, user1, user2);

        campaignManager.sponsor(campaignId, user2);

        assertEq(campaignManager.getSponsor(campaignId, user2), user1);
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

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

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

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

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

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        assertFalse(campaignManager.canSponsor(campaignId, user1, address(0)));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.InvalidConfiguration.selector);
        campaignManager.sponsor(campaignId, address(0));
    }

    function testCannotSponsorOwnSponsor() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        assertFalse(campaignManager.canSponsor(campaignId, user2, user1));

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.CannotSponsorSponsor.selector);
        campaignManager.sponsor(campaignId, user1);
    }

    function testCannotSponsorAfterCampaignEnds() public {
        addressBook.setVerification(user1, block.timestamp + 10 days);
        addressBook.setVerification(user2, block.timestamp + 10 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 2 days);

        assertFalse(campaignManager.canSponsor(campaignId, user1, user2));

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.sponsor(campaignId, user2);
    }

    function testCannotSponsorSelf() public {
        addressBook.setVerification(user1, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

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

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, someUser);

        assertFalse(campaignManager.canSponsor(campaignId, user1, someUser));
        assertFalse(campaignManager.canSponsor(campaignId, user2, someUser));

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.AlreadyParticipated.selector);
        campaignManager.sponsor(campaignId, someUser);
    }

    function testCannotSponsorUserThatAlreadyClaimed(address randomUser) public {
        vm.assume(randomUser != user1 && randomUser != user2 && randomUser != user3 && randomUser != address(0));

        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(user3, block.timestamp + 100 days);
        addressBook.setVerification(randomUser, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, randomUser);

        vm.prank(randomUser);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(randomUser);
        campaignManager.claim(campaignId);

        assertFalse(campaignManager.canSponsor(campaignId, user1, randomUser));

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.AlreadyParticipated.selector);
        campaignManager.sponsor(campaignId, randomUser);
    }

    function testCanClaim() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);
        addressBook.setVerification(user3, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit WorldCampaignManager.Claimed(campaignId, user2, 20_000_000_000_000_000_000);

        campaignManager.claim(campaignId);

        (, uint256 availableFunds,,,,,,,) = campaignManager.getCampaign(campaignId);

        assertEq(availableFunds, 50 ether - 20_000_000_000_000_000_000);
        assertEq(token.balanceOf(user2), 20_000_000_000_000_000_000);
        assertEq(
            uint8(campaignManager.getClaimStatus(campaignId, user2)),
            uint8(WorldCampaignManager.ClaimStatus.AlreadyClaimed)
        );
        assertEq(token.balanceOf(address(campaignManager)), 50 ether - 20_000_000_000_000_000_000);
    }

    function testClaimRandomness(uint256 lowerBound, uint256 upperBound) public {
        vm.assume(lowerBound < upperBound);

        if (upperBound > 100 ether) {
            token.mint(address(this), upperBound - 100 ether);
        }

        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);
        addressBook.setVerification(user3, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, upperBound, block.timestamp + 10 days, lowerBound, upperBound, upperBound, upperBound
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        campaignManager.claim(campaignId);

        uint256 rewardAmount = token.balanceOf(user2);

        assertTrue(rewardAmount >= lowerBound && rewardAmount <= upperBound);
    }

    function testCanClaimBonus() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);
        addressBook.setVerification(user3, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign( // for this test, bonus threshold == lower bound, so bonus is always awarded
            token,
            50 ether,
            block.timestamp + 10 days,
            1 ether,
            5 ether,
            1 ether,
            20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        campaignManager.claim(campaignId);

        assertEq(token.balanceOf(user2), 20 ether);
    }

    function testCampaignWithExactAmountRewards() public {
        addressBook.setVerification(user1, block.timestamp + 1000);
        addressBook.setVerification(user2, block.timestamp + 1000);
        addressBook.setVerification(user3, block.timestamp + 1000);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 5 ether, 5 ether, 5 ether, 5 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        campaignManager.claim(campaignId);

        uint256 rewardAmount = token.balanceOf(user2);

        assertEq(rewardAmount, 5 ether);
    }

    function testCannotClaimIfHasNotSponsoredYet(address anyAddress) public {
        vm.assume(anyAddress != user1);
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.HasNotSponsoredYet.selector);
        campaignManager.claim(campaignId);
    }

    function testCannotClaimNonExistentCampaign() public {
        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.claim(999);
    }

    function testCannotClaimIfInsufficientFunds() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(user3, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 1 ether, block.timestamp + 10 days, 2 ether, 3 ether, 3 ether, 5 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.InsufficientFunds.selector);
        campaignManager.claim(campaignId);
    }

    function testCannotClaimBonusIfInsufficientFunds() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(user3, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 1 ether, block.timestamp + 10 days, 2 ether, 3 ether, 2 ether, 5 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.InsufficientFunds.selector);
        campaignManager.claim(campaignId);
    }

    function testCannotClaimIfNotSponsored() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.NotSponsored.selector);
        campaignManager.claim(campaignId);
    }

    function testCannotClaimAfterCampaignEnds() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.claim(campaignId);
    }

    function testCannotClaimTwice() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(user3, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        vm.prank(user2);
        campaignManager.claim(campaignId);

        vm.prank(user2);
        vm.expectRevert(WorldCampaignManager.NotSponsored.selector);
        campaignManager.claim(campaignId);
    }

    function testCanEndCampaignEarly() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        campaignManager.endCampaignEarly(campaignId);

        (,,, bool wasEndedEarly,,,,,) = campaignManager.getCampaign(campaignId);

        assertTrue(wasEndedEarly);
    }

    function testOnlyOwnerCanEndCampaignEarly() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        campaignManager.endCampaignEarly(campaignId);
    }

    function testCannotEndCampaignEarlyOnSameBlockItExpires() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 1 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.endCampaignEarly(campaignId);
    }

    function testCannotEndNonExistentCampaignEarly() public {
        vm.expectRevert(WorldCampaignManager.CampaignNotFound.selector);
        campaignManager.endCampaignEarly(999);
    }

    function testCannotEndAlreadyEndedCampaignEarly() public {
        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        campaignManager.endCampaignEarly(campaignId);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.endCampaignEarly(campaignId);

        uint256 secondCampaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.warp(block.timestamp + 11 days);

        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.endCampaignEarly(secondCampaignId);
    }

    function testCannotSponsorOnEndedEarlyCampaign() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        campaignManager.endCampaignEarly(campaignId);

        vm.prank(user1);
        vm.expectRevert(WorldCampaignManager.CampaignEnded.selector);
        campaignManager.sponsor(campaignId, user2);
    }

    function testCanStillClaimOnEndedEarlyCampaign() public {
        addressBook.setVerification(user1, block.timestamp + 100 days);
        addressBook.setVerification(user2, block.timestamp + 100 days);
        addressBook.setVerification(user3, block.timestamp + 100 days);

        uint256 campaignId = campaignManager.createCampaign(
            token, 50 ether, block.timestamp + 10 days, 1 ether, 10 ether, 9 ether, 20 ether
        );

        vm.prank(user1);
        campaignManager.sponsor(campaignId, user2);

        vm.prank(user2);
        campaignManager.sponsor(campaignId, user3);

        campaignManager.endCampaignEarly(campaignId);

        vm.prank(user2);
        campaignManager.claim(campaignId);

        assertEq(
            uint8(campaignManager.getClaimStatus(campaignId, user2)),
            uint8(WorldCampaignManager.ClaimStatus.AlreadyClaimed)
        );
    }
}
