// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

interface IPool {
    /* ========== ENUMS ========== */

    enum Status {
        INACTIVE,
        FROZEN,
        ACTIVE
    }

    /* ========== FUNCTIONS ========== */

    function updateSettlerFee(uint256 fee) external;

    function updateLockTime(uint256 lockTime) external;

    /* ========== EVENTS ========== */

    event StatusChanged(Status previous, Status next);
    event Unlock(uint256 amount);
    event Lock(uint256 amount);
    event LockTimeChanged(uint256 previous, uint256 next);
    event SettlerFeeChanged(uint256 previous, uint256 next);
    event Withdraw(
        address indexed user,
        uint256 shares,
        uint256 amount,
        uint256 penalty
    );
    event Deposit(address indexed user, uint256 amount, uint256 shares);
}
