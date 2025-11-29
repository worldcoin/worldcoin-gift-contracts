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

    /// @notice Thrown when trying to withdraw from a campaign that is still active
    error CampaignActive();

    /// @notice Thrown when a participant has already participated in a campaign
    error AlreadyParticipated();

    /// @notice Thrown when a user tries to sponsor themselves
    error CannotSponsorSelf();

    /// @notice Thrown when an address is not verified
    error NotVerified();

    /// @notice Thrown when a recipient has not been sponsored
    error NotSponsored();

    /// @notice Thrown when there are insufficient funds to process a claim
    error InsufficientFunds();

    /// @notice Thrown when a recipient tries to claim without sponsoring someone first.
    error HasNotSponsoredYet();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                ///
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the WorldCampaignManager is initialized
    event WorldCampaignManagerInitialized(address addressBook);

    /// @notice Emitted when a new campaign is created
    /// @param campaignId The ID of the created campaign
    event CampaignCreated(uint256 indexed campaignId);

    /// @notice Emitted when a campaign is funded
    /// @param campaignId The ID of the campaign
    /// @param amount The amount of funds added to the campaign
    event CampaignFunded(uint256 indexed campaignId, uint256 amount);

    /// @notice Emitted when a campaign ends early
    /// @param campaignId The ID of the campaign
    event CampaignEndedEarly(uint256 indexed campaignId);

    /// @notice Emitted when excess funds are withdrawn from a campaign
    /// @param campaignId The ID of the campaign
    /// @param amount The amount of funds withdrawn
    event ExcessFundsWithdrawn(uint256 indexed campaignId, uint256 amount);

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
    /// @param funds The amount of funds allocated for the campaign
    /// @param endsAt The timestamp when the campaign ends
    /// @param wasEndedEarly Whether the campaign was ended early
    /// @param lowerBound The minimum reward amount
    /// @param upperBound The maximum reward amount
    /// @param randomnessSeed A seed used for randomness in reward calculation
    struct Campaign {
        address token;
        uint256 funds;
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

    /// @notice Stores the reverse mapping of recipient to sponsor for a given campaign
    mapping(uint256 => mapping(address => address)) public getSponsor;

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

        getSponsor[campaignId][recipient] = msg.sender;
        getSponsoredRecipient[campaignId][msg.sender] = recipient;
        getClaimStatus[campaignId][recipient] = ClaimStatus.CanClaim;

        emit Sponsored(campaignId, msg.sender, recipient);
    }

    /// @notice Claim a sponsorship reward in a campaign
    /// @param campaignId The ID of the campaign
    /// @return rewardAmount The amount of the reward claimed
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has already ended
    /// @custom:throws HasNotSponsoredYet Thrown when the recipient has not sponsored anyone yet
    /// @custom:throws NotSponsored Thrown when the recipient has not been sponsored or has already claimed their reward
    function claim(uint256 campaignId) external returns (uint256 rewardAmount) {
        Campaign storage campaign = getCampaign[campaignId];
        address sponsor = getSponsor[campaignId][msg.sender];

        require(campaign.token != address(0), CampaignNotFound());
        require(block.timestamp < campaign.endsAt, CampaignEnded());
        require(getClaimStatus[campaignId][msg.sender] == ClaimStatus.CanClaim, NotSponsored());
        require(getSponsoredRecipient[campaignId][msg.sender] != address(0), HasNotSponsoredYet());

        getClaimStatus[campaignId][msg.sender] = ClaimStatus.AlreadyClaimed;

        if (campaign.lowerBound == campaign.upperBound) {
            rewardAmount = campaign.lowerBound;
        } else {
            uint256 range = campaign.upperBound - campaign.lowerBound;
            uint256 randomness =
                uint256(EfficientHashLib.hash(abi.encodePacked(campaign.randomnessSeed, sponsor, msg.sender)));
            rewardAmount = campaign.lowerBound + (randomness % range);
        }

        require(campaign.funds >= rewardAmount, InsufficientFunds());
        unchecked {
            campaign.funds -= rewardAmount;
        }

        emit Claimed(campaignId, msg.sender, rewardAmount);

        SafeTransferLib.safeTransfer(campaign.token, msg.sender, rewardAmount);
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
    /// @param initialDeposit The initial deposit amount
    /// @param endTimestamp The timestamp when the campaign ends
    /// @param lowerBound The minimum reward amount
    /// @param upperBound The maximum reward amount
    /// @param seed A seed used for randomness in reward calculation
    /// @return campaignId The ID of the created campaign
    /// @custom:throws InvalidConfiguration Thrown when the configuration is invalid
    function createCampaign(
        IERC20 token,
        uint256 initialDeposit,
        uint256 endTimestamp,
        uint256 lowerBound,
        uint256 upperBound,
        uint256 seed
    ) external onlyOwner returns (uint256 campaignId) {
        require(initialDeposit > 0, InvalidConfiguration());
        require(lowerBound <= upperBound, InvalidConfiguration());
        require(address(token) != address(0), InvalidConfiguration());
        require(endTimestamp > block.timestamp, InvalidConfiguration());

        unchecked {
            campaignId = nextCampaignId++;
        }

        getCampaign[campaignId] = Campaign({
            token: address(token),
            funds: initialDeposit,
            endsAt: endTimestamp,
            wasEndedEarly: false,
            lowerBound: lowerBound,
            upperBound: upperBound,
            randomnessSeed: seed
        });

        emit CampaignCreated(campaignId);

        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), initialDeposit);
    }

    /// @notice Fund an existing campaign
    /// @param campaignId The ID of the campaign to fund
    /// @param amount The amount of funds to add to the campaign
    /// @custom:throws InvalidConfiguration Thrown when the amount is zero
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has already ended
    /// @dev For simplicity, we allow any address to fund a campaign
    function fundCampaign(uint256 campaignId, uint256 amount) external {
        Campaign storage campaign = getCampaign[campaignId];

        require(amount > 0, InvalidConfiguration());
        require(campaign.token != address(0), CampaignNotFound());
        require(block.timestamp < campaign.endsAt, CampaignEnded());

        unchecked {
            campaign.funds += amount;
        }
        emit CampaignFunded(campaignId, amount);
        SafeTransferLib.safeTransferFrom(campaign.token, msg.sender, address(this), amount);
    }

    /// @notice Withdraw unclaimed funds from a ended campaign
    /// @param campaignId The ID of the campaign to withdraw from
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has not yet ended
    function withdrawUnclaimedFunds(uint256 campaignId) external onlyOwner {
        Campaign storage campaign = getCampaign[campaignId];

        require(campaign.token != address(0), CampaignNotFound());
        require(block.timestamp > campaign.endsAt, CampaignActive());

        uint256 unclaimedFunds = campaign.funds;
        campaign.funds = 0;

        emit ExcessFundsWithdrawn(campaignId, unclaimedFunds);

        SafeTransferLib.safeTransfer(campaign.token, msg.sender, unclaimedFunds);
    }

    /// @notice End a campaign early
    /// @param campaignId The ID of the campaign to end early
    /// @custom:throws CampaignNotFound Thrown when the campaign does not exist
    /// @custom:throws CampaignEnded Thrown when the campaign has already ended
    /// @dev Note that ending a campaign early does not prevent already sponsored recipients from claiming their rewards.
    function endCampaignEarly(uint256 campaignId) external onlyOwner {
        Campaign storage campaign = getCampaign[campaignId];

        require(campaign.token != address(0), CampaignNotFound());
        require(!campaign.wasEndedEarly && block.timestamp < campaign.endsAt, CampaignEnded());

        campaign.wasEndedEarly = true;

        emit CampaignEndedEarly(campaignId);
    }
}
