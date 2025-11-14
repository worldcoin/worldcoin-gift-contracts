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

    error AlreadyParticipated();
    error CannotSponsorSelf();

    error NotVerified();

    error NotSponsored();
    error AlreadyClaimed();

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

    struct Campaign {
        address token;
        address fundedFrom;
        uint256 endsAt;
        uint256 lowerBound;
        uint256 upperBound;
        uint256 randomnessSeed;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              CONFIG STORAGE                            ///
    //////////////////////////////////////////////////////////////////////////////

    IAddressBook public immutable addressBook;

    /// @notice The next campaign ID to be assigned
    uint256 private nextCampaignId = 1;

    /// @notice A mapping of campaign ID to Campaign details
    mapping(uint256 => Campaign) public getCampaign;

    /// @notice Stores the sponsored recipient for a given campaign and sponsor
    mapping(uint256 => mapping(address => address)) public getSponsoredRecipient;

    /// @notice Tracks if a recipient has already been sponsored for a given campaign
    mapping(uint256 => mapping(address => bool)) public hasBeenSponsored;

    /// @notice Tracks if a recipient has already claimed a sponsorship reward for a given campaign
    mapping(uint256 => mapping(address => bool)) public hasClaimedSponsorshipReward;

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONSTRUCTOR                              ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Create a new WorldCampaignManager contract
    constructor(IAddressBook _addressBook) {
        require(address(_addressBook) != address(0), InvalidConfiguration());

        addressBook = _addressBook;

        _initializeOwner(msg.sender);

        emit WorldCampaignManagerInitialized(address(addressBook));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               MAIN LOGIC                                ///
    //////////////////////////////////////////////////////////////////////////////

    function sponsor(uint256 campaignId, address recipient) external {
        Campaign memory campaign = getCampaign[campaignId];

        require(recipient != msg.sender, CannotSponsorSelf());
        require(recipient != address(0), InvalidConfiguration());
        require(campaign.token != address(0), CampaignNotFound());
        require(block.timestamp < campaign.endsAt, CampaignEnded());
        require(!hasBeenSponsored[campaignId][recipient], AlreadyParticipated());
        require(!hasClaimedSponsorshipReward[campaignId][recipient], AlreadyParticipated());
        require(addressBook.addressVerifiedUntil(recipient) >= block.timestamp, NotVerified());
        require(addressBook.addressVerifiedUntil(msg.sender) >= block.timestamp, NotVerified());
        require(getSponsoredRecipient[campaignId][msg.sender] == address(0), AlreadyParticipated());

        hasBeenSponsored[campaignId][recipient] = true;
        getSponsoredRecipient[campaignId][msg.sender] = recipient;

        emit Sponsored(campaignId, msg.sender, recipient);
    }

    function claim(uint256 campaignId) external {
        Campaign memory campaign = getCampaign[campaignId];

        require(campaign.token != address(0), CampaignNotFound());
        require(block.timestamp < campaign.endsAt, CampaignEnded());
        require(hasBeenSponsored[campaignId][msg.sender], NotSponsored());
        require(!hasClaimedSponsorshipReward[campaignId][msg.sender], AlreadyClaimed());

        hasClaimedSponsorshipReward[campaignId][msg.sender] = true;

        uint256 range = campaign.upperBound - campaign.lowerBound;
        uint256 randomness =
            uint256(EfficientHashLib.hash(abi.encodePacked(block.prevrandao, campaign.randomnessSeed, msg.sender)));
        uint256 rewardAmount = campaign.lowerBound + (randomness % range);

        emit Claimed(campaignId, msg.sender, rewardAmount);

        SafeTransferLib.safeTransferFrom(campaign.token, campaign.fundedFrom, msg.sender, rewardAmount);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CONFIG LOGIC                             ///
    //////////////////////////////////////////////////////////////////////////////

    function createCampaign(
        IERC20 token,
        address fundsOrigin,
        uint256 endTimestamp,
        uint256 lowerBound,
        uint256 upperBound,
        uint256 seed
    ) external onlyOwner returns (uint256 campaignId) {
        require(lowerBound < upperBound, InvalidConfiguration());
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
            lowerBound: lowerBound,
            upperBound: upperBound,
            randomnessSeed: seed
        });

        emit CampaignCreated(campaignId);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              INTERNAL LOGIC                            ///
    //////////////////////////////////////////////////////////////////////////////
}
