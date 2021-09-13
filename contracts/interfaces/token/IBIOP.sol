// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IBIOP {
    /* ========== EVENTS ========== */

    event Initialized(
        address vest,
        address swap,
        address utilization,
        address ico,
        address amm,
        address dexRewards
    );
}
