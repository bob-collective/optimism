// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";

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

    function migrateLiquidity() internal {
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
        migrateLiquidity();
        vm.stopBroadcast();

        require(L1UsdcBridgeMigration(l1UsdcBridgeProxy).deposits(l1Usdc, l2Usdc) == 0, "Liquidity not migrated");
    }
}

// forge test --match-test test_L1UsdcBridgeMigration --fork-url https://eth.llamarpc.com
contract L1UsdcBridgeMigrationTest is Test, L1UsdcBridgeMigrationScriptBase {
    address constant l1UsdcBridgeProxyOwner = 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194;

    address constant tokenPool = 0xc2e3A3C18ccb634622B57fF119a1C8C7f12e8C0c;
    address constant tokenPoolOwner = 0x44835bBBA9D40DEDa9b64858095EcFB2693c9449;

    uint64 remoteChainSelector = 3849287863852499584;

    function test_L1UsdcBridgeMigration() public {
        uint256 migrationAmount = L1UsdcBridgeMigration(l1UsdcBridgeProxy).deposits(l1Usdc, l2Usdc);

        vm.startPrank(tokenPoolOwner);
        ITokenPool(tokenPool).setLiquidityProvider(remoteChainSelector, l1UsdcBridgeProxy);
        vm.stopPrank();

        vm.startPrank(l1UsdcBridgeProxyOwner);
        migrateLiquidity();
        vm.stopPrank();

        // check there is no liquidity left in the contract
        assertEq(L1UsdcBridgeMigration(l1UsdcBridgeProxy).deposits(l1Usdc, l2Usdc), 0);
        assertEq(ITokenPool(tokenPool).getLockedTokensForChain(remoteChainSelector), migrationAmount);
    }
}
