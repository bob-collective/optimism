// SPDX-License-Identifier: APACHE-2.0
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice The parts of the USDC interface we need.
interface IPartialUsdc is IERC20 {
    function mint(address _to, uint256 _amount) external;
    function burn(uint256 _amount) external;
}
