// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface ITieredICO {
    /* ========== STRUCTS ========== */

    struct Tier {
        uint256 allocation;
        uint256 usdPrice;
        uint256 etherPrice;
    }

    /* ========== FUNCTIONS ========== */

    function startSale() external;

    /* ========== EVENTS ========== */

    event Initialized(uint256 start, uint256 end);
    event TierSet(
        uint256 tierIndex,
        uint256 allocation,
        uint256 usdPrice,
        uint256 etherPrice
    );
    event Collect(uint256 raisedFunds, uint256 leftovers);
    event Investment(uint256 investment, uint256 tokens);
}
