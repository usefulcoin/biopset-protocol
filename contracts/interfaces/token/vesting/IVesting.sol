// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IVesting {
    /* ========== FUNCTIONS ========== */

    function startVesting() external;

    function currentlyVested() external view returns (uint256);

    function claim() external;

    function claimTo(address beneficiary) external;

    /* ========== EVENTS ========== */

    event Claim(address indexed to, uint256 amount);
    event Started(uint256 start, uint256 end);
}
