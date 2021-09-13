// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IvBIOP is IERC20 {
    /* ========== FUNCTIONS ========== */

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function delegate(address to) external;

    /* ========== EVENTS ========== */

    event Claim(address from, address indexed to, uint256 amount);
}
