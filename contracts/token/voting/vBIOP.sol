// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/token/voting/IvBIOP.sol";

/**
 * @dev Implementation of the {IvBIOP} interface.
 *
 * A non-transferable EIP-20 token that is meant to showcase
 * the voting power of an individual. The owner of the contract
 * is assumed to be the {DAOStaking} contract that mints and
 * burns the corresponding vBIOP amounts depending on deposits
 * and withdraws respectively.
 *
 * The contract also supports a basic voting power delegation
 * system whereby a person's vBIOP balance can be delegated to
 * another individual. Given that the DAO system of BIOP does
 * not conduct a traditional voting process, it is okay for
 * power to be "duplicated" across the delegator and the delagatee
 * as it cannot be exploited.
 */
contract vBIOP is IvBIOP, ERC20, ProtocolConstants, Ownable {
    /* ========== STATE VARIABLES ========== */

    // The amount a particular address has via delegates
    mapping(address => uint256) public delegates;

    // The person a user is delegating their power to
    mapping(address => address) public delegation;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initializes the OpenZeppelin ERC20 token with the name
     * and symbol of the voting token.
     */
    constructor() public ERC20("Voting BIOP", "vBIOP") {}

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the voting power a user has including their
     * delegated power.
     */
    function balanceOf(address user)
        public
        view
        override(ERC20, IERC20)
        returns (uint256)
    {
        return super.balanceOf(user).add(delegates[user]);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Mints the specified amount of tokens to the staker, re-delegating
     * their new amount if they are already delegating to another user.
     *
     * Requirements:
     *
     * - the caller must be the DAO staking contract
     */
    function mint(address to, uint256 amount) external override onlyOwner {
        address delegate = delegation[msg.sender];
        if (delegate != address(0)) _redelegate(delegate, amount);

        _mint(to, amount);
    }

    /**
     * @dev Burns the specified amount of tokens from the staker to unlock their stake
     * and subtracts the same amount from their delegate.
     *
     * Requirements:
     *
     * - the caller must be the DAO staking contract
     */
    function burn(address from, uint256 amount)
        external
        override
        clearDelegate(amount)
        onlyOwner
    {
        _burn(from, amount);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to set a person as their vote delegate.
     *
     * Requirements:
     *
     * - the caller must have a non-zero balance to delegate
     */
    function delegate(address to)
        external
        override
        clearDelegate(super.balanceOf(msg.sender))
    {
        uint256 _delegation = super.balanceOf(msg.sender);

        require(_delegation != 0, "vBIOP::delegate: Inexistent Delegation");

        delegates[to] = delegates[to].add(_delegation);

        delegation[msg.sender] = to;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Overrides the standard OpenZeppelin ERC-20 transfer method to prohibit transfers.
     */
    function _transfer(
        address,
        address,
        uint256
    ) internal override {
        revert("vBIOP::_transfer: Transfers Prohibited");
    }

    /**
     * @dev Overrides the standard OpenZeppelin ERC-20 approve method to prohibit approvals.
     */
    function _approve(
        address,
        address,
        uint256
    ) internal override {
        revert("vBIOP::_approve: Approvals Prohibited");
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Removes the specified amount of vote delegates from the user's delegation.
     */
    function _undelegate(address user, uint256 amount) private {
        address previousDelegate = delegation[user];
        delegates[previousDelegate] = delegates[previousDelegate].sub(amount);
    }

    /**
     * @dev Re-delegates the newly minted amount to the existing delegate of the user.
     */
    function _redelegate(address _delegate, uint256 amount) private {
        delegates[_delegate] = delegates[_delegate].add(amount);
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev Clears the delegation of the caller by the specified amount.
     */
    modifier clearDelegate(uint256 amount) {
        if (delegation[msg.sender] != address(0))
            _undelegate(msg.sender, amount);
        _;
    }
}
