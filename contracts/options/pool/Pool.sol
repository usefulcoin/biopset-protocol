// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/options/pool/IPool.sol";
import "../../interfaces/options/utilization/IUtilizationRewards.sol";

/**
 * @dev Implementation of the {IPool} interface.
 *
 * Allows users to stake funds to the pool and utilizes a share-based
 * system to dilute option rewards to all holders. The pool also acts as
 * a non-transferrable EIP-20 token that can be tracked by traditional wallets.
 *
 * Applies a penalty to stakers who withdraw early and awards staking durations
 * with BIOP via the utilization reward contract.
 */
contract Pool is IPool, ERC20, ProtocolConstants, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    /* ========== STATE VARIABLES ========== */

    // The token the pool supports
    IERC20 public immutable token;

    // The address of the utilization reward contract
    IUtilizationRewards public immutable utilization;

    // The treasury address fees should be sent to
    address payable public immutable treasury;

    // Re-declared name and symbols to allow "overriding" of the OpenZeppelin ERC20 interface
    string private _name;
    string private _symbol;

    // Locked amount for pending options & rewards
    uint256 public locked;

    // The amount of time each staker should lock their funds for to not be penalized
    uint256 public lockTime;

    // The settler fee of the protocol
    uint256 public settlerFee;

    // The status of the pool
    Status public status = Status.ACTIVE;

    // Whether the pool is native
    bool public isNative;

    // The timestamp each user has their liquidity locked for
    mapping(address => uint256) public lock;

    // The block each user has deposited in, used for utilization rewards
    mapping(address => uint256) public depositBlock;

    // Whether a user has interacted with the protocol, used for utilization rewards
    mapping(address => bool) public interacted;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {token}, {utilization}, {treasury}, and
     * transfers ownership of the contract to the DAO.
     *
     * Additionally, the pool's token's name and symbol are retrieved to calculate
     * the new pool name and symbols by prefixing the name with "Binary Option " and
     * the symbol with "b".
     */
    constructor(
        ERC20 _token,
        IUtilizationRewards _utilization,
        address payable _treasury,
        address _dao
    ) public ERC20("", "") {
        require(
            _token != IERC20(0) &&
                _utilization != IUtilizationRewards(0) &&
                _treasury != address(0) &&
                _dao != address(0),
            "Pool::constructor: Misconfiguration"
        );

        if (_token == ERC20(_ETHER)) {
            _name = "Binary Option Ether";
            _symbol = "bETH";
            isNative = true;
        } else {
            _name = string(abi.encodePacked("Binary Option ", _token.name()));
            _symbol = string(abi.encodePacked("b", _token.symbol()));
        }

        token = _token;
        utilization = _utilization;
        treasury = _treasury;

        transferOwnership(_dao);
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the name of the pool token.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the pool token.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the current balance of the pool.
     */
    function balance() public view returns (uint256) {
        if (token == IERC20(_ETHER)) return address(this).balance;
        else return token.balanceOf(address(this));
    }

    /**
     * @dev Returns the available balance of the pool by subtracting the amount locked from it
     */
    function available() public view returns (uint256) {
        return balance().sub(locked);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to stake in the pool and acquire a share of it.
     *
     * Emits an {Staked} event indicating the amount newly staked in the pool and
     * the number of shares received.
     *
     * Requirements:
     *
     * - the call is not re-entrant
     * - the amount staked is non-zero
     */
    function stake(uint256 amount) external payable nonReentrant {
        amount = _validateAmount(amount);

        require(amount != 0, "Pool::stake: Non-Zero Deposit Required");

        if (isNative && !interacted[msg.sender])
            utilization.trackParticipation(msg.sender);

        lock[msg.sender] = block.timestamp + lockTime;

        if (isNative) depositBlock[msg.sender] = block.number;

        uint256 _totalSupply = totalSupply();

        uint256 shares;
        if (_totalSupply != 0)
            shares = amount.mul(_totalSupply).div(balance().sub(msg.value));
        else shares = amount;

        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount, shares);
    }

    /**
     * @dev Allows a user to withdraw their shares from a pool, realizing any profit
     * or loss acquired in the duration of staking. Additionally applies a penalty
     * in case the withdrawal was performed early and rewards utilization depending
     * on the number of blocks elapsed since the last deposit.
     *
     * Emits an {Withdraw} event indicating the amount of shares withdrawn and the equivalent
     * amount of pool tokens including any penalty applied.
     *
     * Requirements:
     *
     * - the call is not re-entrant
     * - the amount withdrawn is non-zero
     * - the user has enough shares to satisfy the withdrawal share amount
     * - the pool has enough unlocked tokens to satisfy the withdrawal token amount
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares != 0, "Pool::withdraw: Non-Zero Shares Required");

        _burn(msg.sender, shares);

        uint256 amount = shares.mul(balance()).div(totalSupply());

        require(
            amount <= available(),
            "Pool::withdraw: Insufficient Available Funds"
        );

        uint256 penalty;
        if (block.timestamp < lock[msg.sender])
            penalty = amount.mul(_EARLY_WITHDRAW_PENALTY).div(
                _MAX_BASIS_POINTS
            );

        if (isNative) {
            uint256 blocksElapsed = block.number - depositBlock[msg.sender];

            if (blocksElapsed >= 1)
                utilization.trackOptionRewards(msg.sender, blocksElapsed);

            depositBlock[msg.sender] = 0;
        }

        lock[msg.sender] = 0;

        emit Withdraw(msg.sender, shares, amount, penalty);

        _send(msg.sender, amount - penalty);
        if (penalty != 0) _send(treasury, penalty);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows the settler fee to be updated by the DAO.
     *
     * Emits a {SettlerFeeChanged} event indicating the previous and next settler fees.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function updateSettlerFee(uint256 _settlerFee) external override onlyOwner {
        emit SettlerFeeChanged(settlerFee, _settlerFee);

        settlerFee = _settlerFee;
    }

    /**
     * @dev Allows the lock time to be updated by the DAO.
     *
     * Emits a {LockTimeChanged} event indicating the previous and next lock times.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the new lock time must be non-zero to prevent arbitrage
     */
    function updateLockTime(uint256 _lockTime) external override onlyOwner {
        require(
            _lockTime != 0,
            "Option::updateLockTime: Lock Time Cannot Be Zero"
        );

        emit LockTimeChanged(lockTime, _lockTime);

        lockTime = _lockTime;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Overrides the default OpenZeppelin ERC20 functionality to prevent transfers
     */
    function _transfer(
        address,
        address,
        uint256
    ) internal override {
        revert("Pool::_transfer: Transfers Prohibited");
    }

    /**
     * @dev Overrides the default OpenZeppelin ERC20 functionality to prevent approvals
     */
    function _approve(
        address,
        address,
        uint256
    ) internal override {
        revert("Pool::_approve: Approvals Prohibited");
    }

    /**
     * @dev Allows an amount to be locked in the pool
     *
     * Emits a {Locked} event indicating the amount locked
     */
    function _lock(uint256 amount) internal {
        locked = locked.add(amount);

        emit Lock(amount);
    }

    /**
     * @dev Allows an amount to be unlocked in the pool
     *
     * Emits an {Unlocked} event indicating the amount locked
     */
    function _unlock(uint256 amount) internal {
        locked = locked.sub(amount);

        emit Unlock(amount);
    }

    /**
     * @dev Performs an outward transfer of the specified amount to the recipient.
     */
    function _send(address payable recipient, uint256 amount) internal {
        if (token == IERC20(_ETHER)) recipient.sendValue(amount);
        else token.safeTransfer(recipient, amount);
    }

    /**
     * @dev Validates the input amount depending on the pool type, retrieving
     * the necessary funds in the process if non-native.
     */
    function _validateAmount(uint256 amount) internal view returns (uint256) {
        if (token == IERC20(_ETHER)) amount = msg.value;
        else require(msg.value == 0, "Pool::stake: Ether on Token");
        return amount;
    }
}
