// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IVXSwap {
    /* ========== STRUCTS ========== */

    struct Swap {
        address claimant;
        uint256 amount;
    }

    /* ========== FUNCTIONS ========== */

    function startSwap() external;

    /* ========== EVENTS ========== */

    event Swapped(address biopVX, uint256 amount);
    event Initialized(uint256 end);
    event Sweep(uint256 leftovers, uint256 biopPerBlock);
}
