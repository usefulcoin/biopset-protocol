// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IUtilizationRewards {
    /* ========== FUNCTIONS ========== */

    function trackGas(uint256 eth) external;

    function trackOptionRewards(address user, uint256 blocks) external;

    function trackParticipation(address user) external;

    function setEthBiopRate(uint256 _rate) external;

    function setPeriodMaximum(uint256 _periodMaximum) external;

    /* ========== EVENTS ========== */

    event PeriodChanged(uint256 previous, uint256 next);
    event RateChanged(uint256 previous, uint256 next);
    event StakingTracked(address user, uint256 reward);
    event ParticipationTracked(address user);
    event GasTracked(address user, uint256 reward);
    event OptionRewardClaimed(address user, uint256 reward);
    event GasRewardClaimed(address user, uint256 reward);
}
