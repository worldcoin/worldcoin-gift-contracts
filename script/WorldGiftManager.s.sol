// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import {WorldGiftManager, IERC20, IAddressBook} from "../src/WorldGiftManager.sol";

contract WorldGiftManagerScript is Script, Config {
    WorldGiftManager public giftManager;

    function setUp() public {}

    function run() public {
        _loadConfig("./deployments.toml", true);

        address token = config.get("token").toAddress();
        address addressBook = config.get("addressBook").toAddress();

        vm.startBroadcast();

        giftManager = new WorldGiftManager(
            IERC20(token),
            IAddressBook(addressBook)
        );

        vm.stopBroadcast();
    }
}
