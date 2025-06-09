// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Test} from 'forge-std/Test.sol';
import {console2 as console} from 'forge-std/console2.sol';

import {L1StandardBridge} from 'src/L1/L1StandardBridge.sol';
import {IOptimismMintableERC20} from 'src/universal/IOptimismMintableERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface Proxy {
  function upgradeTo(address _implementation) external;
}

interface ProxyAdmin {
  function upgrade(address payable _proxy, address _implementation) external;
}

contract L1StandardBridgeExt is L1StandardBridge {
  function migrateLiquidity(address token, uint256 amount) external {}
}

contract L1StandardBridgeMigrationScriptBase {
  address payable constant l1StandardBridgeProxy =
    payable(0x3F6cE1b36e5120BBc59D0cFe8A5aC8b6464ac1f7);

  address payable constant l1ProxyAdmin =
    payable(0x0d9f416260598313Be6FDf6B010f2FbC34957Cd0);

  function upgradeAndMigrateLiquidity() internal returns (L1StandardBridgeExt) {
    L1StandardBridgeExt newL1StandardBridge = new L1StandardBridgeExt();

    console.log(
      'Deploying new L1StandardBridge at address: %s',
      address(newL1StandardBridge)
    );

    ProxyAdmin(l1ProxyAdmin).upgrade(
      l1StandardBridgeProxy,
      address(newL1StandardBridge)
    );

    return newL1StandardBridge;
  }
}

// forge script  scripts/L1StandardBridgeMigration.s.sol --tc L1StandardBridgeMigrationScript --fork-url
// https://1rpc.io/eth --sender 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194 --broadcast -vvv
contract L1StandardBridgeMigrationScript is
  Script,
  L1StandardBridgeMigrationScriptBase
{
  function run() public {
    vm.startBroadcast();
    upgradeAndMigrateLiquidity();
    vm.stopBroadcast();
  }
}

// forge test --match-test test_L1StandardBridgeMigration --fork-url https://1rpc.io/eth
contract L1StandardBridgeMigrationTest is
  Test,
  L1StandardBridgeMigrationScriptBase
{
  function test_L1StandardBridgeMigration() public {
    vm.startPrank(0xC91482A96e9c2A104d9298D1980eCCf8C4dc764E); // Conduit / BOB Multisig
    upgradeAndMigrateLiquidity();
    vm.stopPrank();
  }
}
