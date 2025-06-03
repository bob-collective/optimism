// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";

import { L1UsdcBridge } from "src/L1/L1UsdcBridge.sol";
import { L1UsdcBridgeMigration } from "src/L1/L1UsdcBridgeMigration.sol";

interface IL1ChugSplashProxy {
    function setCode(bytes memory _code) external;
}

interface ITokenPool {
    function setLiquidityProvider(uint64 remoteChainSelector, address liquidityProvider) external;

    function getLiquidityProvider(uint64 remoteChainSelector) external view returns (address);

    function getLockedTokensForChain(uint64 remoteChainSelector) external view returns (uint256);
}

// TODO: Need to wait for Chainlink to add l1UsdcBridgeProxy as a liquidity provider on the token pool

contract L1UsdcBridgeMigrationScriptBase {
    address payable constant l1UsdcBridgeProxy = payable(0x450D55a4B4136805B0e5A6BB59377c71FC4FaCBb);

    address constant l1Usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant l2Usdc = 0xe75D0fB2C24A55cA1e3F96781a2bCC7bdba058F0;

    // TODO: Get the correct amount of in flight withdrawals
    uint256 constant inFlightWithdrawals = 1000000;

    function migrateLiquidity(uint256 _inFlightWithdrawals) internal {
        IL1ChugSplashProxy(l1UsdcBridgeProxy).setCode(type(L1UsdcBridgeMigration).runtimeCode);

        L1UsdcBridgeMigration(l1UsdcBridgeProxy).migrateLiquidity(_inFlightWithdrawals);
    }
}

// forge script  scripts/L1UsdcBridgeMigration.s.sol --tc L1UsdcBridgeMigrationScript --fork-url
// https://1rpc.io/eth --sender 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194 --broadcast -vvv
contract L1UsdcBridgeMigrationScript is Script, L1UsdcBridgeMigrationScriptBase {
    function run() public {
        require(L1UsdcBridge(l1UsdcBridgeProxy).paused(), "Bridge is not paused");

        // Set 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194 as the broadcasting account
        vm.startBroadcast();
        migrateLiquidity(inFlightWithdrawals);
        vm.stopBroadcast();
    }
}

// forge test --match-test test_L1UsdcBridgeMigration --fork-url https://1rpc.io/eth
contract L1UsdcBridgeMigrationTest is Test, L1UsdcBridgeMigrationScriptBase {
    address constant l1UsdcBridgeProxyOwner = 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194;

    address constant tokenPool = 0xc2e3A3C18ccb634622B57fF119a1C8C7f12e8C0c;
    address constant tokenPoolOwner = 0x44835bBBA9D40DEDa9b64858095EcFB2693c9449;

    uint64 remoteChainSelector = 3849287863852499584;

    function test_L1UsdcBridgeMigration() public {
        // pause the bridge
        vm.startPrank(l1UsdcBridgeProxyOwner);
        L1UsdcBridge(l1UsdcBridgeProxy).pause();
        vm.stopPrank();

        require(L1UsdcBridge(l1UsdcBridgeProxy).paused(), "Bridge is not paused");

        uint256 lockedTokensInCCIPBridgeBeforeMigration =
            ITokenPool(tokenPool).getLockedTokensForChain(remoteChainSelector);

        uint256 migrationAmount =
            L1UsdcBridgeMigration(l1UsdcBridgeProxy).deposits(l1Usdc, l2Usdc) - inFlightWithdrawals;

        // Liquidity provider has been set, so we dont need this now
        // vm.startPrank(tokenPoolOwner);
        // ITokenPool(tokenPool).setLiquidityProvider(remoteChainSelector, l1UsdcBridgeProxy);
        // vm.stopPrank();

        vm.startPrank(l1UsdcBridgeProxyOwner);
        migrateLiquidity(inFlightWithdrawals);
        vm.stopPrank();

        // check the correct amount of liquidity has been migrated
        assertEq(L1UsdcBridgeMigration(l1UsdcBridgeProxy).deposits(l1Usdc, l2Usdc), inFlightWithdrawals);
        assertEq(
            ITokenPool(tokenPool).getLockedTokensForChain(remoteChainSelector),
            lockedTokensInCCIPBridgeBeforeMigration + migrationAmount
        );
    }
}
