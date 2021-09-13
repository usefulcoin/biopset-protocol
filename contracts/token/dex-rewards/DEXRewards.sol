// SPDX-License-Identifier: MIT

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/token/dex-rewards/IDEXRewards.sol";

/**
 * @dev Implementation of the {IDEXRewards} interface.
 *
 * A basic staking reward mechanism based on MasterChef by SushiSwap
 * that allows new rewards to be added to it dynamically by anyone.
 *
 * Contains some minor adjustments to make the implementation
 * more optimal and security standard compliant.
 */
contract DEXRewards is IDEXRewards, ProtocolConstants, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // The DEX Reward Token (BIOP)
    IERC20 public immutable biop;

    // BIOP tokens distributed per block
    uint256 public biopPerBlock;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The block number when BIOP mining starts.
    uint256 public startBlock;

    // The block number when BIOP mining ends.
    uint256 public endBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Tracks whether LP token has already been added
    mapping(IERC20 => bool) public exists;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the value of the {biop} token.
     *
     * Applies basic sanitization by ensuring it has been strictly set and transfers
     * ownership of the contract to the DAO.
     */
    constructor(IERC20 _biop, address _dao) public {
        require(
            _biop != IERC20(0) && _dao != address(0),
            "DEXRewards::constructor: Misconfiguration"
        );

        biop = _biop;

        transferOwnership(_dao);
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the number of pools that are active.
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Returns the reward multiplier, the difference in blocks here as its linear.
     */
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    /**
     * @dev Returns the amount of pending BIOP rewards for the front-end
     */
    function pendingBIOP(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accBiopPerShare = pool.accBiopPerShare;

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        uint256 _endBlock = endBlock;
        uint256 validBlock = block.number > _endBlock
            ? _endBlock
            : block.number;

        if (validBlock > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                validBlock
            );
            uint256 biopReward = multiplier
                .mul(biopPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accBiopPerShare = accBiopPerShare.add(
                biopReward.mul(_DEX_REWARD_ACCURACY).div(lpSupply)
            );
        }
        return
            user.amount.mul(accBiopPerShare).div(_DEX_REWARD_ACCURACY).sub(
                user.rewardDebt
            );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows anyone to fund the contract with a new reward period if the previous
     * one has ended.
     *
     * Emits a {Funded} event indicating the new reward period's details.
     *
     * Requirements:
     *
     * - the amount supplied must be wholly divisible by the reward per block
     * - the previous reward period must have ended
     * - the total block duration must be within a threshold
     */
    function fund(uint256 amount, uint256 _biopPerBlock) external override {
        require(
            amount % _biopPerBlock == 0,
            "DEXRewards::fund: Incorrect Reward Specified"
        );

        require(
            block.number >= endBlock,
            "DEXRewards::fund: Reward Period Active"
        );

        uint256 totalBlocks = amount.div(_biopPerBlock);

        require(
            _DEX_REWARD_BLOCK_THRESHOLD >= totalBlocks,
            "DEXRewards::fund: Too Many Blocks"
        );

        if (endBlock != 0) massUpdatePools();

        biopPerBlock = _biopPerBlock;

        uint256 _startBlock;
        startBlock = _startBlock = block.number + _GRACE_PERIOD;
        endBlock = _startBlock.add(totalBlocks);

        emit Funded(msg.sender, amount, _biopPerBlock, totalBlocks);

        biop.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Synchronizes all active pools of the system.
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @dev Synchronizes a single pool of the system.
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 _endBlock = endBlock;
        uint256 validBlock = block.number > _endBlock
            ? _endBlock
            : block.number;

        if (validBlock <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = validBlock;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, validBlock);
        uint256 biopReward = multiplier
            .mul(biopPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        pool.accBiopPerShare = pool.accBiopPerShare.add(
            biopReward.mul(_DEX_REWARD_ACCURACY).div(lpSupply)
        );

        pool.lastRewardBlock = validBlock;
    }

    /**
     * @dev Allows users to deposit pool tokens to acquire BIOP rewards.
     *
     * Emits a {Deposit} event indicating the pool the funds were deposited to
     * as well as the amount deposited.
     *
     * Requirements:
     *
     * - the amount to be deposited must be non-zero
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_amount != 0, "DEXRewards::deposit: Improper Deposit Amount");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accBiopPerShare)
                .div(_DEX_REWARD_ACCURACY)
                .sub(user.rewardDebt);
            _safeBiopTransfer(msg.sender, pending);
        }

        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accBiopPerShare).div(
            _DEX_REWARD_ACCURACY
        );

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @dev Allows users to withdraw pool tokens.
     *
     * Emits a {Withdraw} event indicating the pool the funds were withdrawn from
     * as well as the amount withdrawn.
     *
     * Requirements:
     *
     * - the user must have enough deposit to cover the withdrawal
     * - the amount to be withdrawn must be non-zero
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(
            user.amount >= _amount && _amount != 0,
            "DEXRewards::withdraw: Improper Withdrawal Amount"
        );

        updatePool(_pid);

        uint256 pending = user
            .amount
            .mul(pool.accBiopPerShare)
            .div(_DEX_REWARD_ACCURACY)
            .sub(user.rewardDebt);

        _safeBiopTransfer(msg.sender, pending);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accBiopPerShare).div(
            _DEX_REWARD_ACCURACY
        );

        emit Withdraw(msg.sender, _pid, _amount);

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @dev Withdraws all pool tokens in the contract, ignoring rewards.
     *
     * Emits an {EmergencyWithdraw} event indicating the amount withdrawn
     * as well as the pool they were withdrawn from.
     *
     * Requirements:
     *
     * - the user must have a non-zero deposit to the pool
     */
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 refund = userInfo[_pid][msg.sender].amount;

        require(refund != 0, "DEXRewards::emergencyWithdraw: No Refund");

        delete userInfo[_pid][msg.sender];

        emit EmergencyWithdraw(msg.sender, _pid, refund);

        pool.lpToken.safeTransfer(address(msg.sender), refund);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows a new reward pool to be added.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the LP token must not have already been added
     * - the rewards must be active
     */
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) external override onlyOwner {
        require(!exists[_lpToken], "DEXRewards::add: LP Token Already Added");
        require(
            block.number <= endBlock,
            "DEXRewards::add: Rewards Not Active"
        );

        exists[_lpToken] = true;

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 _startBlock = startBlock;

        uint256 lastRewardBlock = block.number > _startBlock
            ? block.number
            : _startBlock;

        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accBiopPerShare: 0
            })
        );
    }

    /**
     * @dev Allows an existing pool's allocation to be re-adjusted.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the LP token must have already been added
     */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external override onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];

        require(
            exists[pool.lpToken],
            "DEXRewards::set: LP Token Does Not Exist"
        );

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);

        pool.allocPoint = _allocPoint;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Safely transfers BIOP outward from the contract,
     * accounting for potential inaccuracies in the division calculations
     * of the contract.
     */
    function _safeBiopTransfer(address _to, uint256 _amount) private {
        uint256 biopBal = biop.balanceOf(address(this));

        if (_amount > biopBal) {
            if (biopBal == 0) return;

            biop.safeTransfer(_to, biopBal);
        } else {
            biop.safeTransfer(_to, _amount);
        }
    }
}
