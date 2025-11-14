// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Config} from "forge-std/Config.sol";
import {Script} from "forge-std/Script.sol";
import {IAddressBook} from "../src/interfaces/IAddressBook.sol";
import {WorldCampaignManager} from "../src/WorldCampaignManager.sol";

contract WorldCampaignManagerScript is Script, Config {
    WorldCampaignManager public campaignManager;

    function setUp() public {}

    function run() public {
        _loadConfig("./deployments.toml", true);

        address addressBook = config.get("addressBook").toAddress();

        vm.startBroadcast();

        campaignManager = new WorldCampaignManager(IAddressBook(addressBook));

        vm.stopBroadcast();
    }
}
