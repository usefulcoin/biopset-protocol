// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IBondingCurveAMM {
    /* ========== EVENTS ========== */

    event Purchase(
        address indexed user,
        uint256 amountEth,
        uint256 amountToken,
        uint256 feeEth
    );
    event Sale(
        address indexed user,
        uint256 amountToken,
        uint256 amountEth,
        uint256 feeEth
    );
    event Reserves(uint256 eth, uint256 biop, uint256 initialSoldSupply);
}
