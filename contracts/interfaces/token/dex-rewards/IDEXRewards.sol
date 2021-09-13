// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDEXRewards {
    /* ========== STRUCTS ========== */

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BIOPs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBiopPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBiopPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. BIOPs to distribute per block.
        uint256 lastRewardBlock; // Last block number that BIOPs distribution occurs.
        uint256 accBiopPerShare; // Accumulated BIOPs per share, times 1e12. See below.
    }

    /* ========== FUNCTIONS ========== */

    function fund(uint256 amount, uint256 biopPerBlock) external;

    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    /* ========== EVENTS ========== */

    event Funded(
        address indexed funder,
        uint256 amount,
        uint256 biopPerBlock,
        uint256 totalBlockDuration
    );
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
}
