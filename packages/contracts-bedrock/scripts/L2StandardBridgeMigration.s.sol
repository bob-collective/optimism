// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Test} from 'forge-std/Test.sol';
import {console2 as console} from 'forge-std/console2.sol';

import {L2StandardBridge} from 'src/L2/L2StandardBridge.sol';
import {IOptimismMintableERC20} from 'src/universal/IOptimismMintableERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ProxyAdmin {
  function upgrade(address payable _proxy, address _implementation) external;
}

contract L2StandardBridgeExt is L2StandardBridge {
  mapping(address => address) public tokenMinter;

  function setMinter(address minter, address l2Token) external {
    tokenMinter[minter] = l2Token;
  }

  function mint(address account, uint256 amount) external {
    IOptimismMintableERC20(tokenMinter[msg.sender]).mint(account, amount);
  }

  function burn(address account, uint256 amount) external {
    IOptimismMintableERC20(tokenMinter[msg.sender]).burn(account, amount);
  }
}

interface IBurnMintCCIP {
  function mint(address account, uint256 amount) external;
  function burn(uint256 amount) external;
  function burn(address account, uint256 amount) external;
  function burnFrom(address account, uint256 amount) external;
}

contract TokenWrapper is IBurnMintCCIP {
  address payable immutable bridge;

  constructor(address payable _bridge) {
    bridge = _bridge;
  }

  function mint(address account, uint256 amount) external {
    L2StandardBridgeExt(bridge).mint(account, amount);
  }

  function burn(uint256 amount) external {
    L2StandardBridgeExt(bridge).burn(msg.sender, amount);
  }

  function burn(address account, uint256 amount) external {
    L2StandardBridgeExt(bridge).burn(account, amount);
  }

  function burnFrom(address account, uint256 amount) external {
    L2StandardBridgeExt(bridge).burn(account, amount);
  }
}

contract L2StandardBridgeMigrationScriptBase {
  address payable constant l2StandardBridgeProxy =
    payable(0x4200000000000000000000000000000000000010);

  address payable constant l2StandardBridgeProxyAdmin =
    payable(0x4200000000000000000000000000000000000018);

  address constant l2Wbtc = 0x03C7054BCB39f7b2e5B2c7AcB37583e32D70Cfa3;

  function deployAndUpgrade() internal returns (L2StandardBridgeExt) {
    L2StandardBridgeExt newl2StandardBridge = new L2StandardBridgeExt();

    console.log(
      'Deploying new L2StandardBridge at address: %s',
      address(newl2StandardBridge)
    );

    ProxyAdmin(l2StandardBridgeProxyAdmin).upgrade(
      l2StandardBridgeProxy,
      address(newl2StandardBridge)
    );

    return newl2StandardBridge;
  }
}

// forge script  scripts/L2StandardBridgeMigration.s.sol --tc L2StandardBridgeMigrationScript --fork-url
// https://1rpc.io/eth --sender 0xC73b6E6ec346f9f1A07D2e7A4380858D7BEa0194 --broadcast -vvv
contract L2StandardBridgeMigrationScript is
  Script,
  L2StandardBridgeMigrationScriptBase
{
  function run() public {
    vm.startBroadcast();
    deployAndUpgrade();
    vm.stopBroadcast();
  }
}

// forge test --match-test test_L2StandardBridgeMigration --fork-url https://rpc.gobob.xyz
contract L2StandardBridgeMigrationTest is
  Test,
  L2StandardBridgeMigrationScriptBase
{
  function test_L2StandardBridgeMigration() public {
    TokenWrapper tokenWrapper = new TokenWrapper(l2StandardBridgeProxy);

    vm.startPrank(0x432C1fe0a868c8eeEC2c73F59743f88fb07B561b); // Conduit / BOB Multisig
    deployAndUpgrade();
    L2StandardBridgeExt(l2StandardBridgeProxy).setMinter(
      address(tokenWrapper),
      l2Wbtc
    );
    vm.stopPrank();

    tokenWrapper.mint(vm.addr(1), 1000);

    IERC20 l2WbtcToken = IERC20(l2Wbtc);
    console.log('L2 WBTC balance: %s', l2WbtcToken.balanceOf(vm.addr(1)));
  }
}
