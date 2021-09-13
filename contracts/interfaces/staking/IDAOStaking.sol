// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IDAOStaking {
    /* ========== FUNCTIONS ========== */

    function notifyRewardAmount() external payable;

    function setDistributorStatus(address _distributor, bool _status) external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event DistributorChanged(address distributor, bool status);
}
