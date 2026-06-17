// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SoulPet.sol";

/// @title SoulPet 部署脚本
/// @notice 用于把 SoulPet 合约部署到 Pharos（Atlantic 测试网或主网）。
///         运行：forge script script/DeploySoulPet.s.sol:DeploySoulPet \
///               --rpc-url <rpc> --private-key $PRIVATE_KEY --broadcast
contract DeploySoulPet is Script {
    function run() external {
        vm.startBroadcast();

        SoulPet soulPet = new SoulPet();

        console.log("=== Deploy Result ===");
        console.log("SoulPet address:", address(soulPet));
        console.log("Deployer:", msg.sender);
        console.log("Next pet id:", soulPet.nextId());

        vm.stopBroadcast();
    }
}
