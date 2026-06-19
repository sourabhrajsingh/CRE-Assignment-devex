// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PriceSnapshot} from "../src/Snapshot.sol";

contract DeployPriceSnapshot is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address Forwarder = vm.envAddress("FORWARDER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        PriceSnapshot priceSnapshot = new PriceSnapshot(Forwarder);

        vm.stopBroadcast();

        console.log("=====================================");
        console.log("PriceSnapshot deployed to:", address(priceSnapshot));
        console.log("Forwarder used:", Forwarder);
        console.log("=====================================");
    }
}
