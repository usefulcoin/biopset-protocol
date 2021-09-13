// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITreasury {
    /* ========== FUNCTIONS ========== */

    function send(
        IERC20 token,
        address payable destination,
        uint256 amount
    ) external;

    function updateTax(uint256 tax) external;

    /* ========== EVENTS ========== */

    event Funding(address indexed depositor, uint256 amount);
    event NativeTransfer(
        address indexed destination,
        uint256 amount,
        uint256 tax
    );
    event TokenTransfer(
        address token,
        address indexed destination,
        uint256 amount
    );
    event TaxChanged(uint256 previous, uint256 next);
}
