// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/token/legacy-swap/IVXSwap.sol";
import "../../interfaces/token/dex-rewards/IDEXRewards.sol";

/**
 * @dev Implementation of the {IVXSwap} interface.
 *
 * Allows users to swap their legacy VX tokens to the new
 * V5 token via a pre-determined exchange rate and allocation
 * per user.
 *
 * The swap allocation each user has can be partially consumed
 * and is unique per address and per user. The swap is active
 * for a set period after which unconsumed tokens are send to
 * DEX stakers as a reward.
 */
contract VXSwap is IVXSwap, ProtocolConstants, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ========== */

    // The BIOP token
    IERC20 public immutable biopV5;

    // The reward contract to send leftover tokens to
    IDEXRewards public immutable dexRewards;

    // The team address
    address public immutable team;

    // The legacy token allocations
    mapping(address => mapping(IERC20 => uint256)) public biopVX;

    // Time until swaps are possible
    uint256 public end;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {biopV5}, {dexRewards}, {team}, and
     * transfers ownership of the contract to the BIOP token.
     *
     * It performs rudimentary input sanitization by ensuring the input
     * addresses are non-zero. Additionally, the swap allocations are
     * all summed up and ensured to be equal to the total swap allocation
     * of the contract.
     */
    constructor(
        IERC20 _biopV5,
        IDEXRewards _dexRewards,
        IERC20[] memory _biopVX,
        Swap[][] memory _swaps
    ) public {
        require(
            _biopV5 != IERC20(0) && _dexRewards != IDEXRewards(0),
            "VXSwap::constructor: Misconfiguration"
        );

        biopV5 = _biopV5;
        dexRewards = _dexRewards;
        team = msg.sender;

        uint256 sum;
        for (uint256 i = 0; i < _biopVX.length; i++) {
            for (uint256 j = 0; j < _swaps[i].length; j++) {
                uint256 amount = _swaps[i][j].amount;

                require(
                    amount != 0,
                    "VXSwap::constructor: Incorrect Swap Amount"
                );

                biopVX[_swaps[i][j].claimant][_biopVX[i]] = amount;

                sum = sum.add(amount);
            }
        }

        require(
            sum == _SWAP_ALLOCATION,
            "VXSwap::constructor: Insufficient Allocation Provided"
        );

        transferOwnership(address(_biopV5));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Swaps the specified amount of tokens from the legacy biop VX
     * token to the new V5 format based on the allocation the user has.
     *
     * Emits a {Swap} event indicating the token version swapped as well
     * as the amount.
     *
     * Requirements:
     *
     * - the swap must be active
     * - the caller must have sufficient allocation
     */
    function swap(IERC20 _biopVX, uint256 amount) external {
        require(block.timestamp <= end, "VXSwap::swap: Swap has ended");

        uint256 allocation = biopVX[msg.sender][_biopVX];

        require(
            allocation >= amount,
            "VXSwap::swap: Insufficient Swap Allocation"
        );

        biopVX[msg.sender][_biopVX] = allocation - amount;

        emit Swapped(address(_biopVX), amount);

        _biopVX.safeTransferFrom(msg.sender, address(this), amount);
        biopV5.safeTransfer(msg.sender, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Initiates the swap period.
     *
     * Emits an {Initialized} event indicating when the swap ends.
     *
     * Requirements:
     *
     * - the caller must be the BIOP token
     */
    function startSwap() external override onlyOwner {
        uint256 _end;
        end = _end = block.timestamp + _SWAP_DURATION;

        emit Initialized(_end);

        renounceOwnership();
    }

    /**
     * @dev Sweeps the remaining swap amount after the swap period ends.
     *
     * Emits a {Sweep} event indicating the amount swept as well as the
     * per block reward for the reward contract.
     *
     * Requirements:
     *
     * - the swap must not be active
     * - the caller must be the team address
     * - there must be leftovers in the contract
     */
    function sweep(uint256 biopPerBlock) external {
        require(block.timestamp > end, "VXSwap::sweep: Swap active");
        require(msg.sender == team, "VXSwap::sweep: Insufficient Priviledges");

        uint256 leftovers = biopV5.balanceOf(address(this));

        require(leftovers != 0, "VXSwap::sweep: Nothing to sweep");

        emit Sweep(leftovers, biopPerBlock);

        biopV5.approve(address(dexRewards), leftovers);
        dexRewards.fund(leftovers, biopPerBlock);
    }
}
