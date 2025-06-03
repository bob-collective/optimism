// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { L1UsdcBridge } from "src/L1/L1UsdcBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITokenPool {
    function provideLiquidity(uint64 remoteChainSelector, uint256 amount) external;

    function getLockedTokensForChain(uint64 remoteChainSelector) external view returns (uint256);
}

// Upgrade to L1UsdcBridge that allows to migrate all liquidity into the CCIP token pool
contract L1UsdcBridgeMigration is L1UsdcBridge {
    // The address of the CCIP token pool
    address private constant tokenPool = 0xc2e3A3C18ccb634622B57fF119a1C8C7f12e8C0c;

    // The remote chain selector for BOB
    uint64 private constant remoteChainSelector = 3849287863852499584;

    function migrateLiquidity(uint256 inFlightWithdrawals) external onlyOwner {
        // get the total amount of liquidity in the contract
        uint256 totalLiquidityAmount = deposits[l1Usdc][l2Usdc];

        // calculate the amount of tokens to migrate
        uint256 migrationAmount = totalLiquidityAmount - inFlightWithdrawals;

        // get the amount of tokens locked in the CCIP bridge before the migration
        uint256 lockedTokensInTokenPoolBeforeMigration =
            ITokenPool(tokenPool).getLockedTokensForChain(remoteChainSelector);

        // approve the token pool to move the tokens
        IERC20(l1Usdc).approve(tokenPool, migrationAmount);

        // migrate the liquidity into the token pool
        ITokenPool(tokenPool).provideLiquidity(remoteChainSelector, migrationAmount);

        // remove the liquidity that was migrated
        deposits[l1Usdc][l2Usdc] -= migrationAmount;

        // only the in flight withdrawals should be left in the contract
        require(deposits[l1Usdc][l2Usdc] == inFlightWithdrawals, "Liquidity not migrated");
        require(
            ITokenPool(tokenPool).getLockedTokensForChain(remoteChainSelector)
                == lockedTokensInTokenPoolBeforeMigration + migrationAmount,
            "Liquidity nott migrated"
        );
    }
}
