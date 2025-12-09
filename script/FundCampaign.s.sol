// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {WorldCampaignManager} from "../src/WorldCampaignManager.sol";

contract FundCampaignScript is Script {
    // Deployed WorldCampaignManager contract address
    address campaignManagerAddress = 0xcf2Ab38031cFe6e5A3b7f17b0f6406F8ecF43f57;
    // Token address to use for rewards
    address tokenAddress = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003; // WLD
    // Campaign parameters
    uint256 campaignId = 3;

    function run() public {
        // TODO set to correct amount
        uint256 amount = 0.01 ether;

        WorldCampaignManager campaignManager = WorldCampaignManager(
            campaignManagerAddress
        );
        IERC20 token = IERC20(tokenAddress);

        vm.startBroadcast();

        // First, approve the campaign manager to spend tokens
        token.approve(address(campaignManager), amount);

        // fund the campaign
        campaignManager.fundCampaign(campaignId, amount);

        vm.stopBroadcast();
    }
}
