// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/token/vesting/IVesting.sol";

/**
 * @dev Implementation of the {IVesting} interface.
 *
 * A liner vesting implementation with no cliff period
 * which is meant to be activated by the BIOP token
 * when the vesting amount is minted to the contract.
 */
contract Vesting is IVesting, ProtocolConstants, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable biop;
    address public immutable team;

    uint256 public start;
    uint256 public end;
    uint256 public claimed;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {biop} and the {team} & transfers ownership of
     * the contract to the BIOP token.
     *
     * The input address is sanitized by ensuring it does not represent the zero
     * address.
     */
    constructor(IERC20 _biop) public {
        require(_biop != IERC20(0), "Vesting::constructor: Misconfiguration");

        biop = _biop;
        team = msg.sender;

        transferOwnership(address(_biop));
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the amount of investment that has been vested by the
     * user. This is expressed in investment token units and would need
     * to be converted to tokens vested via the {getTokenAmount} function.
     */
    function currentlyVested() public view override returns (uint256) {
        if (block.timestamp >= end) return _DEV_ALLOCATION - claimed;
        else if (block.timestamp > start)
            return
                _DEV_ALLOCATION.mul(block.timestamp - start).div(
                    _VEST_DURATION
                ) - claimed;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Claims the currently vested tokens for the caller.
     */
    function claim() external override {
        _claim(msg.sender);
    }

    /**
     * @dev Claims the currently vested tokens for the caller to the beneficiary.
     */
    function claimTo(address beneficiary) external override {
        _claim(beneficiary);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Begins the vesting period.
     *
     * Emits a {Started} event indicating the start and end of the
     * vesting duration.
     *
     * It is assumed that the contract has been sufficiently funded
     * to award the vesting amounts as this function is called by
     * the BIOP token.
     *
     * Requirements:
     *
     * - the caller must be the BIOP token
     */
    function startVesting() external override onlyOwner {
        uint256 _start;
        uint256 _end;
        start = _start = block.timestamp;
        end = _end = block.timestamp + _VEST_DURATION;

        emit Started(_start, _end);

        renounceOwnership();
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Claims the amount of vested tokens the caller has and transfers them
     * to the listed beneficiary.
     *
     * Emits a {Claim} event indicating the amount claimed as well as to whom.
     *
     * Requirements:
     *
     * - the caller must be the team address
     * - the caller must have a non-zero amount of tokens vested
     */
    function _claim(address beneficiary) private {
        require(
            msg.sender == team,
            "Vesting::_claim: Insufficient Priviledges"
        );

        uint256 vested = currentlyVested();

        require(vested != 0, "Vesting::_claim: Nothing to vest");

        claimed += vested;

        emit Claim(beneficiary, vested);

        biop.safeTransfer(beneficiary, vested);
    }
}
