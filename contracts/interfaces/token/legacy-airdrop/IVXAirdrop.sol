// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IVXAirdrop {
    /* ========== STRUCTS ========== */

    struct Swap {
        address claimant;
        uint256 amount;
    }

    /* ========== FUNCTIONS ========== */

    function startAirdrop() external;

    /* ========== EVENTS ========== */

    event Initialized(uint256 end);
    event Claim(address indexed claimer, uint256 amount);
    event Sweep(uint256 leftovers);
}
