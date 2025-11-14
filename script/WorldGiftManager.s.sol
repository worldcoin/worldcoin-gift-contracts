// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {WorldGiftManager} from "../src/WorldGiftManager.sol";

contract WorldGiftManagerScript is Script {
    WorldGiftManager public giftManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        giftManager = new WorldGiftManager();

        vm.stopBroadcast();
    }
}
