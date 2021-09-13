// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../shared/ProtocolConstants.sol";

import "../interfaces/staking/IDAOStaking.sol";
import "../interfaces/token/voting/IvBIOP.sol";

/**
 * @dev Implementation of the {IDAOStaking} interface.
 *
 * A modified Synthetix based staking reward mechanism that supports
 * distribution and addition of rewards using the native asset of the
 * blockchain the contract is deployed to rather than a token.
 */
contract DAOStaking is
    IDAOStaking,
    ProtocolConstants,
    Ownable,
    ReentrancyGuard
{
    using Address for address payable;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // The voting BIOP token
    IvBIOP public immutable vBIOP;

    // The token to be staked, BIOP
    IERC20 public immutable stakingToken;

    // A block delay to prevent flash-loan manipulation of voting tokens
    mapping(address => uint256) public blockDelay;

    // Synthetix Variables
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration = _DAO_STAKING_INITIAL_DURATION;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // A customized reward distributor role for multiple members
    mapping(address => bool) public rewardDistributors;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {vBIOP}, {stakingToken} and initializes the status
     * of the first reward distributors. Afterwards, transfers ownership of the contract
     * to the DAO.
     *
     * Performs basic input sanitization by ensuring that the input addresses are strictly set.
     *
     * Emits a {DistributorChanged} event for each distributor that is newly added to the contract's list.
     */
    constructor(
        IvBIOP _vBIOP,
        IERC20 _stakingToken,
        address[] memory _initialDistributors,
        address _dao
    ) public {
        require(
            _vBIOP != IvBIOP(0) &&
                _stakingToken != IERC20(0) &&
                _dao != address(0),
            "DAOStaking::constructor: Misconfiguration"
        );

        vBIOP = _vBIOP;
        stakingToken = _stakingToken;

        for (uint256 i = 0; i < _initialDistributors.length; i++) {
            address distributor = _initialDistributors[i];

            require(
                distributor != address(0),
                "DAOStaking::constructor: Incorrect Distributors"
            );

            rewardDistributors[distributor] = true;

            emit DistributorChanged(distributor, true);
        }

        transferOwnership(_dao);
    }

    /* ========== VIEWS ========== */

    /**
     * @dev See: Synthetix
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        uint256 _periodFinish = periodFinish;
        return
            block.timestamp < _periodFinish ? block.timestamp : _periodFinish;
    }

    /**
     * @dev See: Synthetix
     */
    function rewardPerToken() public view returns (uint256) {
        uint256 _totalSupply = vBIOP.totalSupply();

        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(_DAO_STAKING_ACCURACY)
                    .div(_totalSupply)
            );
    }

    /**
     * @dev See: Synthetix
     */
    function earned(address account) public view returns (uint256) {
        return
            vBIOP
                .balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(_DAO_STAKING_ACCURACY)
                .add(rewards[account]);
    }

    /**
     * @dev See: Synthetix
     */
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to acquire rewards by staking BIOP to the contract and immediately
     * awards the user with the non-transferrable voting BIOP equivalent.
     *
     * Emits a {Staked} event in accordance with the Synthetix contract.
     *
     * Requirements:
     *
     * - the amount staked must be non-zero
     */
    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        blockDelay[msg.sender] = block.number;

        emit Staked(msg.sender, amount);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        vBIOP.mint(msg.sender, amount);
    }

    /**
     * @dev Allows a user to withdraw their staked BIOP from the contract and
     * immediately burns the voting BIOP equivalent from the user.
     *
     * Emits a {Withdrawn} event in accordance with the Synthetix contract.
     *
     * Requirements:
     *
     * - the amount withdrawn must be non-zero
     * - the block delay for staking must have passed
     */
    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        require(
            block.number >= blockDelay[msg.sender] + _DAO_STAKING_DELAY,
            "DAOStaking::withdraw: Withdrawal Prevented"
        );

        emit Withdrawn(msg.sender, amount);

        vBIOP.burn(msg.sender, amount);
        stakingToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev See: Synthetix
     *
     * Instead of a token transfer, a native asset transfer is performed for the reward.
     */
    function getReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            emit RewardPaid(msg.sender, reward);
            msg.sender.sendValue(reward);
        }
    }

    /**
     * @dev See: Synthetix
     */
    function exit() external {
        withdraw(vBIOP.balanceOf(msg.sender));
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev See: Synthetix
     *
     * Instead of a dedicated address, multiple addresses can be reward distributors at once.
     */
    function notifyRewardAmount()
        external
        payable
        override
        updateReward(address(0))
    {
        require(
            rewardDistributors[msg.sender],
            "DAOStaking::notifyRewardAmount: Insufficient Priviledges"
        );

        uint256 reward = msg.value;

        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = address(this).balance;
        require(
            rewardRate <= balance.div(rewardsDuration),
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    /**
     * @dev Allows the reward duration to be changed by the DAO.
     *
     * Emits a {RewardsDurationUpdated} event in accordance with the Synthetix contract.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the contract must not have an active reward period
     */
    function setRewardsDuration(uint256 _rewardsDuration)
        external
        override
        onlyOwner
    {
        require(
            block.timestamp > periodFinish,
            "DAOStaking::setRewardsDuration: Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /**
     * @dev Allows the status of a distributor to be adjusted by the DAO.
     *
     * Emits a {DistributorChanged} event indicating the distributor's address and
     * their new status.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function setDistributorStatus(address _distributor, bool _status)
        external
        override
        onlyOwner
    {
        rewardDistributors[_distributor] = _status;

        emit DistributorChanged(_distributor, _status);
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev Updates the rewards of a particular account as well as the global state of the contract on each call.
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}
