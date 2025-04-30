// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";

import { L1UsdcBridgeMigration } from "src/L1/L1UsdcBridgeMigration.sol";

interface IL1ChugSplashProxy {
    function setCode(bytes memory _code) external;
}

// TODO: Need to wait for Chainlink to add l1UsdcBridgeProxy as a liquidity provider on the token pool

contract L1UsdcBridgeMigrationScriptBase {
    address payable constant l1UsdcBridgeProxy = payable(0x450D55a4B4136805B0e5A6BB59377c71FC4FaCBb);

    function deployL1UsdcBridgeMigration() internal {
        IL1ChugSplashProxy(l1UsdcBridgeProxy).setCode(type(L1UsdcBridgeMigration).runtimeCode);

        L1UsdcBridgeMigration(l1UsdcBridgeProxy).migrateLiquidity();
    }
}

// forge script  scripts/L1UsdcBridgeMigration.s.sol --tc L1UsdcBridgeMigrationScript --fork-url
// https://eth.llamarpc.com --sender 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194 --broadcast -vvv
contract L1UsdcBridgeMigrationScript is Script, L1UsdcBridgeMigrationScriptBase {
    function run() public {
        // Set 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194 as the broadcasting account
        vm.startBroadcast();
        deployL1UsdcBridgeMigration();
        vm.stopBroadcast();
    }
}

// forge test --match-test test_L1UsdcBridgeMigration --fork-url https://eth.llamarpc.com
contract L1UsdcBridgeMigrationTest is Test, L1UsdcBridgeMigrationScriptBase {
    address constant l1UsdcBridgeProxyOwner = 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194;

    function test_L1UsdcBridgeMigration() public {
        vm.startPrank(l1UsdcBridgeProxyOwner);
        deployL1UsdcBridgeMigration();
        vm.stopPrank();
    }
}
