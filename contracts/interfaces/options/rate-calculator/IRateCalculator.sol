// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IRateCalculator {
    /* ========== FUNCTIONS ========== */

    function calculateMaxMultiplier() external view returns (uint256);

    function calculateRate(
        uint256 poolBalance,
        uint256 openCalls,
        uint256 openPuts,
        uint256 amount,
        uint256 rounds,
        bool isCall,
        uint256 eth
    ) external view returns (uint256);
}
