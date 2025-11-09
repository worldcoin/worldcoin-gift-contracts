// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import {WorldGiftManager} from "../src/WorldGiftManager.sol";
import {IAddressBook} from "../src/interfaces/IAddressBook.sol";

contract WorldGiftManagerScript is Script, Config {
    WorldGiftManager public giftManager;

    function setUp() public {}

    function run() public {
        _loadConfig("./deployments.toml", true);

        address addressBook = config.get("addressBook").toAddress();

        vm.startBroadcast();

        giftManager = new WorldGiftManager(IAddressBook(addressBook));

        vm.stopBroadcast();
    }
}
