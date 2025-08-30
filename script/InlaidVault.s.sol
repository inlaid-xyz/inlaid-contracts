// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {InlaidVault} from "../src/InlaidVault.sol";
import "../src/interfaces/IMuonClient.sol";

contract InlaidVaultScript is Script {
    function setUp() public {}

    function run() public {
        address underlyingToken = 0x60CfED01ce2804988F9BDf966B1E396c25Ca9B64;
        uint256 muonAppId = uint256(1);
        IMuonClient.PublicKey memory muonPublicKey = IMuonClient.PublicKey({
            x: 1,
            parity: 1
        });
        address muonClient = 0x1b5343e85e3ebD20CCD1776359a3725089b6dBB5;

        vm.createSelectFork("fuji");
        vm.startBroadcast();
        new InlaidVault(underlyingToken, muonAppId, muonPublicKey, muonClient);
        vm.stopBroadcast();
    }
}
