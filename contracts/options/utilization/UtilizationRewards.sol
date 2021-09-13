// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/options/factory/IOptionFactory.sol";
import "../../interfaces/options/utilization/IUtilizationRewards.sol";

/**
 * @dev Implementation of the {IUtilizationRewards} interface.
 *
 * Awards utilization of the BIOP protocol by distributing BIOP rewards
 * to them depending on the action they take.
 *
 * Applies a period-based throttling on the outpour of rewards that is
 * configurable by the DAO.
 */
contract UtilizationRewards is IUtilizationRewards, ProtocolConstants, Ownable {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */

    // The BIOP token rewarded
    IERC20 public immutable biop;

    // The BIOP Option Factory to track access control
    IOptionFactory public immutable factory;

    // Current BIOP per ETH Rate
    uint256 public rate;

    // Current Option Staking Reward
    uint256 public optionStakingReward;

    // Period's Current Total
    uint256 public periodTotal;

    // Maximum Reward Per Period
    uint256 public periodMaximum;

    // Latest Period Time
    uint256 public periodTime = block.timestamp;

    // Amassed gas rewards in ETH
    mapping(address => uint256) public gasRewards;

    // Amassed option rewards in BIOP
    mapping(address => uint256) public optionRewards;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {biop}, {factory}, and transfers ownership of the
     * contract to the {_dao}.
     *
     * The input addresses are properly sanitized to ensure no misconfiguration can arise.
     */
    constructor(
        IERC20 _biop,
        IOptionFactory _factory,
        address _dao
    ) public {
        require(
            _biop != IERC20(0) &&
                _factory != IOptionFactory(0) &&
                _dao != address(0),
            "UtilizationRewards::constructor: Misconfiguration"
        );

        biop = _biop;
        factory = _factory;

        transferOwnership(_dao);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to claim their gas rewards by evaluating their
     * BIOP equivalent using a DAO-controlled ETH -> BIOP rate.
     *
     * Emits a {GasRewardClaimed} event indicating the amount claimed.
     *
     * Requirements:
     *
     * - the caller must have non-zero rewards to claim
     */
    function claimGasRewards() external {
        uint256 rewards = gasRewards[tx.origin];

        require(
            rewards != 0,
            "UtilizationRewards::claimGasRewards: Insufficient Reward"
        );

        uint256 claimable = _claimable(rewards);
        gasRewards[tx.origin] = rewards.sub(claimable);

        uint256 biopReward = claimable.mul(rate).div(1 ether);

        emit GasRewardClaimed(tx.origin, biopReward);

        _send(tx.origin, biopReward);
    }

    /**
     * @dev Allows a user to claim their option rewards as expressed
     * in BIOP units.
     *
     * Emits a {OptionRewardClaimed} event indicating the amount claimed.
     *
     * Requirements:
     *
     * - the caller must have non-zero rewards to claim
     */
    function claimOptionRewards() external {
        uint256 rewards = optionRewards[msg.sender];

        require(
            rewards != 0,
            "UtilizationRewards::claimOptionRewards: Insufficient Reward"
        );

        uint256 claimable = _claimable(rewards);
        optionRewards[msg.sender] = rewards.sub(claimable);

        emit OptionRewardClaimed(msg.sender, claimable);

        _send(msg.sender, claimable);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows options to track gas consumed in its native asset
     * denomination
     *
     * Emits a {OptionRewardClaimed} event indicating the amount claimed.
     *
     * Requirements:
     *
     * - the caller must be an option created via the option factory
     */
    function trackGas(uint256 eth) external override {
        require(
            factory.isOption(msg.sender),
            "UtilizationRewards::trackGas: Insufficient Priviledges"
        );

        gasRewards[tx.origin] = gasRewards[tx.origin].add(eth);

        emit GasTracked(tx.origin, eth);
    }

    /**
     * @dev Allows options to track participation awards.
     *
     * Emits a {ParticipationTracked} event indicating the user that was tracked.
     *
     * Requirements:
     *
     * - the caller must be an option created via the option factory
     */
    function trackParticipation(address user) external override {
        require(
            factory.isOption(msg.sender),
            "UtilizationRewards::trackParticipation: Insufficient Priviledges"
        );

        optionRewards[user] = optionRewards[user].add(
            _UTILIZATION_REWARD_PARTICIPATION
        );

        emit ParticipationTracked(user);
    }

    /**
     * @dev Allows options to track participation awards.
     *
     * Emits a {StakingTracked} event indicating the user that was tracked as well as the
     * staking reward they are due.
     *
     * Requirements:
     *
     * - the caller must be an option created via the option factory
     */
    function trackOptionRewards(address user, uint256 blocks)
        external
        override
    {
        require(
            factory.isOption(msg.sender),
            "UtilizationRewards::trackOptionRewards: Insufficient Priviledges"
        );

        uint256 reward = optionStakingReward.mul(1 + _sqrt(blocks));

        optionRewards[user] = optionRewards[user].add(reward);

        emit StakingTracked(user, reward);
    }

    /**
     * @dev Allows the DAO to update the ETH/BIOP rate for gas claims.
     *
     * Emits a {RateChanged} event indicating the previous and new rates.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function setEthBiopRate(uint256 _rate) external override onlyOwner {
        emit RateChanged(rate, _rate);

        rate = _rate;
    }

    /**
     * @dev Allows the DAO to update the maximum period at which rewards
     * should reset.
     *
     * Emits a {PeriodChanged} event indicating the previous and new periods.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function setPeriodMaximum(uint256 _periodMaximum)
        external
        override
        onlyOwner
    {
        periodTotal = 0;

        emit PeriodChanged(periodMaximum, _periodMaximum);

        periodMaximum = _periodMaximum;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Calculates the reward amount that is claimable based on the
     * current period and the reward amount consumed in the period.
     */
    function _claimable(uint256 amount) private returns (uint256) {
        if (periodTime.add(_UTILIZATION_REWARD_PERIOD) <= block.timestamp) {
            periodTime = block.timestamp;
            periodTotal = 0;
        }

        uint256 available = periodMaximum - periodTotal;

        if (amount > available) amount = available;

        periodTotal = periodTotal.add(amount);

        return amount;
    }

    /**
     * @dev Sends the specified amount of BIOP to the recipient safely,
     * accounting for potentially insufficient balance.
     */
    function _send(address recipient, uint256 amount) private {
        uint256 available = biop.balanceOf(address(this));
        if (amount > available) amount = available;
        biop.safeTransfer(recipient, amount);
    }

    /**
     * @dev See: Uniswap Babylonian Method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
     */
    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
