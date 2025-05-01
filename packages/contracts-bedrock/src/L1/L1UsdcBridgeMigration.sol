// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { L1UsdcBridge } from "src/L1/L1UsdcBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHybridLockReleaseUSDCTokenPool {
    function provideLiquidity(uint64 remoteChainSelector, uint256 amount) external;
}

// Upgrade to L1UsdcBridge that allows to migrate all liquidity into the CCIP token pool
contract L1UsdcBridgeMigration is L1UsdcBridge {
    // The address of the CCIP token pool
    address private constant tokenPool = 0xc2e3A3C18ccb634622B57fF119a1C8C7f12e8C0c;

    // The remote chain selector for BOB
    uint64 private constant remoteChainSelector = 3849287863852499584;

    function migrateLiquidity() external onlyOwner {
        // get the amount of tokens to migrate
        uint256 migrationAmount = deposits[l1Usdc][l2Usdc];

        // approve the token pool to move the tokens
        IERC20(l1Usdc).approve(tokenPool, migrationAmount);

        // // migrate all the liquidity into the token pool
        IHybridLockReleaseUSDCTokenPool(tokenPool).provideLiquidity(remoteChainSelector, migrationAmount);

        // remove the liquidity from this contract by deleting all deposits
        delete deposits[l1Usdc][l2Usdc];
    }
}
