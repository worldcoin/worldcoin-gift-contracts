// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "solady/auth/Ownable.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IAddressBook} from "./interfaces/IAddressBook.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";

/// @title World Campaign Manager
/// @author Miguel Piedrafita
/// @notice Allows World to run global campaigns
contract WorldCampaignManager is Ownable {
    ///////////////////////////////////////////////////////////////////////////////
    ///                                  ERRORS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when trying to create a campaign with invalid configuration
    error InvalidConfiguration();

    /// @notice Thrown when a campaign is not found
    error CampaignNotFound();

    /// @notice Thrown when a campaign has ended
    error CampaignEnded();

    /// @notice Thrown when a participant has already participated in a campaign
    error AlreadyParticipated();

    /// @notice Thrown when a user tries to sponsor themselves
    error CannotSponsorSelf();

    /// @notice Thrown when an address is not verified
    error NotVerified();

    /// @notice Thrown when a recipient has not been sponsored
    error NotSponsored();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the WorldCampaignManager is initialized
    event WorldCampaignManagerInitialized(address addressBook);

    /// @notice Emitted when a new campaign is created
    /// @param campaignId The ID of the created campaign
    event CampaignCreated(uint256 indexed campaignId);

    /// @notice Emitted when a sponsorship is made
    /// @param campaignId The ID of the campaign
    /// @param sponsor The address of the sponsor
    /// @param recipient The address of the recipient being sponsored
    event Sponsored(uint256 indexed campaignId, address indexed sponsor, address indexed recipient);

    /// @notice Emitted when a sponsorship reward is claimed
    /// @param campaignId The ID of the campaign
    /// @param recipient The address of the recipient claiming the reward
    /// @param rewardAmount The amount of the reward claimed
    event Claimed(uint256 indexed campaignId, address indexed recipient, uint256 rewardAmount);

    ///////////////////////////////////////////////////////////////////////////////
    ///                            TYPE DECLARATIONS                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Represents a sponsorship campaign
    /// @param token The ERC20 token used for rewards
    /// @param fundedFrom The address from which rewards will be funded
    /// @param endsAt The timestamp when the campaign ends
    /// @param wasEndedEarly Whether the campaign was ended early
    /// @param lowerBound The minimum reward amount
    /// @param upperBound The maximum reward amount
    /// @param randomnessSeed A seed used for randomness in reward calculation
    struct Campaign {
        address token;
        address fundedFrom;
        uint256 endsAt;
        bool wasEndedEarly;
        uint256 lowerBound;
        uint256 upperBound;
        uint256 randomnessSeed;
    }

    enum ClaimStatus {
        NotSponsored,
        CanClaim,
        AlreadyClaimed
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              CONFIG STORAGE                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice The address book contract that will be used to check verification status
    IAddressBook public immutable addressBook;

    /// @notice The next campaign ID to be assigned
    uint256 private nextCampaignId = 1;

    /// @notice A mapping of campaign ID to Campaign details
    mapping(uint256 => Campaign) public getCampaign;

    /// @notice Stores the sponsored recipient for a given campaign and sponsor
    mapping(uint256 => mapping(address => address)) public getSponsoredRecipient;

    /// @notice Tracks whether a recipient has been sponsored in a given campaign
    mapping(uint256 => mapping(address => ClaimStatus)) public getClaimStatus;

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONSTRUCTOR                              ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Create a new WorldCampaignManager contract
    /// @param _addressBook The address book contract that will be used to check verification status
    /// @custom:throws InvalidConfiguration Thrown when the address book address is zero
    constructor(IAddressBook _addressBook) {
        require(address(_addressBook) != address(0), InvalidConfiguration());

        addressBook = _addressBook;

        _initializeOwner(msg.sender);

        emit WorldCampaignManagerInitialized(address(addressBook));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               MAIN LOGIC                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Sponsor a recipient in a campaign
    /// @param campaignId The ID of the campaign
    /// @param recipient The address of the recipient to be sponsored
    /// @custom:throws CannotSponsorSelf Thrown when a user tries to sponsor themselves
    /// @custom:throws InvalidConfiguration Thrown when the recipient address is zero
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has already ended
    /// @custom:throws AlreadyParticipated Thrown when the recipient has already been sponsored
    /// @custom:throws NotVerified Thrown when either the sponsor or recipient is not verified
    function sponsor(uint256 campaignId, address recipient) external {
        Campaign memory campaign = getCampaign[campaignId];

        require(recipient != msg.sender, CannotSponsorSelf());
        require(recipient != address(0), InvalidConfiguration());
        require(campaign.token != address(0), CampaignNotFound());
        require(addressBook.addressVerifiedUntil(recipient) >= block.timestamp, NotVerified());
        require(block.timestamp < campaign.endsAt && !campaign.wasEndedEarly, CampaignEnded());
        require(addressBook.addressVerifiedUntil(msg.sender) >= block.timestamp, NotVerified());
        require(getSponsoredRecipient[campaignId][msg.sender] == address(0), AlreadyParticipated());
        require(getClaimStatus[campaignId][recipient] == ClaimStatus.NotSponsored, AlreadyParticipated());

        getClaimStatus[campaignId][recipient] = ClaimStatus.CanClaim;
        getSponsoredRecipient[campaignId][msg.sender] = recipient;

        emit Sponsored(campaignId, msg.sender, recipient);
    }

    /// @notice Claim a sponsorship reward in a campaign
    /// @param campaignId The ID of the campaign
    /// @return rewardAmount The amount of the reward claimed
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has already ended
    /// @custom:throws NotSponsored Thrown when the recipient has not been sponsored or has already claimed their reward
    function claim(uint256 campaignId) external returns (uint256 rewardAmount) {
        Campaign memory campaign = getCampaign[campaignId];

        require(campaign.token != address(0), CampaignNotFound());
        require(block.timestamp < campaign.endsAt, CampaignEnded());
        require(getClaimStatus[campaignId][msg.sender] == ClaimStatus.CanClaim, NotSponsored());

        getClaimStatus[campaignId][msg.sender] = ClaimStatus.AlreadyClaimed;

        if (campaign.lowerBound == campaign.upperBound) {
            rewardAmount = campaign.lowerBound;
        } else {
            uint256 range = campaign.upperBound - campaign.lowerBound;
            uint256 randomness = uint256(EfficientHashLib.hash(abi.encodePacked(campaign.randomnessSeed, msg.sender)));
            rewardAmount = campaign.lowerBound + (randomness % range);
        }

        emit Claimed(campaignId, msg.sender, rewardAmount);

        SafeTransferLib.safeTransferFrom(campaign.token, campaign.fundedFrom, msg.sender, rewardAmount);
    }

    /// @notice Check if a sponsor can sponsor a recipient in a campaign
    /// @param campaignId The ID of the campaign
    /// @param sponsor The address of the sponsor
    /// @param recipient The address of the recipient to be sponsored
    /// @return True if the sponsor can sponsor the recipient, false otherwise
    function canSponsor(uint256 campaignId, address sponsor, address recipient) external view returns (bool) {
        Campaign memory campaign = getCampaign[campaignId];

        if (
            recipient == sponsor || campaign.wasEndedEarly || recipient == address(0) || campaign.token == address(0)
                || getClaimStatus[campaignId][recipient] != ClaimStatus.NotSponsored
                || addressBook.addressVerifiedUntil(recipient) < block.timestamp || block.timestamp >= campaign.endsAt
                || addressBook.addressVerifiedUntil(sponsor) < block.timestamp
                || getSponsoredRecipient[campaignId][sponsor] != address(0)
        ) {
            return false;
        }

        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONFIG LOGIC                             ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Create a new sponsorship campaign
    /// @param token The ERC20 token used for rewards
    /// @param fundsOrigin The address from which rewards will be funded
    /// @param endTimestamp The timestamp when the campaign ends
    /// @param lowerBound The minimum reward amount
    /// @param upperBound The maximum reward amount
    /// @param seed A seed used for randomness in reward calculation
    /// @return campaignId The ID of the created campaign
    /// @custom:throws InvalidConfiguration Thrown when the configuration is invalid
    function createCampaign(
        IERC20 token,
        address fundsOrigin,
        uint256 endTimestamp,
        uint256 lowerBound,
        uint256 upperBound,
        uint256 seed
    ) external onlyOwner returns (uint256 campaignId) {
        require(lowerBound <= upperBound, InvalidConfiguration());
        require(fundsOrigin != address(0), InvalidConfiguration());
        require(address(token) != address(0), InvalidConfiguration());
        require(endTimestamp > block.timestamp, InvalidConfiguration());

        unchecked {
            campaignId = nextCampaignId++;
        }

        getCampaign[campaignId] = Campaign({
            token: address(token),
            fundedFrom: fundsOrigin,
            endsAt: endTimestamp,
            wasEndedEarly: false,
            lowerBound: lowerBound,
            upperBound: upperBound,
            randomnessSeed: seed
        });

        emit CampaignCreated(campaignId);
    }

    /// @notice End a campaign early
    /// @param campaignId The ID of the campaign to end early
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has already ended
    /// @dev Note that ending a campaign early does not prevent already sponsored recipients from claiming their rewards.
    function endCampaignEarly(uint256 campaignId) external onlyOwner {
        Campaign storage campaign = getCampaign[campaignId];

        require(campaign.token != address(0), CampaignNotFound());
        require(!campaign.wasEndedEarly && campaign.endsAt > block.timestamp, CampaignEnded());

        campaign.wasEndedEarly = true;
    }
}
