// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/token/legacy-airdrop/IVXAirdrop.sol";
import "../../interfaces/token/dex-rewards/IDEXRewards.sol";

/**
 * @dev Implementation of the {IVXAirdrop} interface.
 *
 * Allows users to claim an airdropped amount of V5 tokens
 * depending on their VX holdings.
 *
 * The airdrop is distributed via a Merkle Proof which the
 * user must validate to acquire the claim. The airdrop is
 * active for a set period of time after which leftover
 * funds are sent as a reward to the DEX staking contract.
 */
contract VXAirdrop is IVXAirdrop, ProtocolConstants, Ownable {
    using SafeERC20 for IERC20;
    using MerkleProof for bytes32[];

    /* ========== STATE VARIABLES ========== */

    // The BIOP Token
    IERC20 public immutable biopV5;

    // The reward contract to distribute leftover funds to
    IDEXRewards public immutable dexRewards;

    // The Merkle Root to validate claims with
    bytes32 public immutable root;

    // The team address
    address public immutable team;

    // Time until airdrop claims are possible
    uint256 public end;

    // A status indicating whether a user has already claimed their airdrop
    mapping(address => bool) public claimed;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {biopV5}, {dexRewards}, {root}, and
     * {team}.
     *
     * All addresses are rudimentary sanitized by ensuring they have been strictly
     * set. Additionally, ownership of the contract is transferred to the BIOP token
     * which is responsible for invoking the {startAirdrop} function of the initialization
     * lifecycle.
     */
    constructor(
        IERC20 _biopV5,
        IDEXRewards _dexRewards,
        bytes32 _root
    ) public {
        require(
            _biopV5 != IERC20(0) && _dexRewards != IDEXRewards(0),
            "VXAirdrop::constructor: Misconfiguration"
        );

        biopV5 = _biopV5;
        dexRewards = _dexRewards;
        root = _root;
        team = msg.sender;

        transferOwnership(address(_biopV5));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to claim their airdrop.
     *
     * Emits a {Claim} event indicating the amount airdropped.
     *
     * Requirements:
     *
     * - the claim period must be active
     * - the caller must not have already claimed their airdrop
     * - the proof they provide for the airdrop must be valid
     */
    function claim(bytes32[] calldata proof, uint256 amount) external {
        require(block.timestamp <= end, "VXAirdrop::claim: Claim has ended");

        require(!claimed[msg.sender], "VXAirdrop::claim: Already Claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));

        require(
            proof.verify(root, leaf),
            "VXAirdrop::claim: Inelligible Airdrop"
        );

        claimed[msg.sender] = true;

        emit Claim(msg.sender, amount);

        biopV5.safeTransfer(msg.sender, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Initiates the airdrop.
     *
     * Emits an {Initialized} event indicating the time the airdrop ends.
     *
     * Requirements:
     *
     * - the caller must be the BIOP token
     */
    function startAirdrop() external override onlyOwner {
        uint256 _end;
        end = _end = block.timestamp + _AIRDROP_DURATION;

        emit Initialized(_end);

        renounceOwnership();
    }

    /**
     * @dev Sweeps any leftover tokens from the airdrop and deposits them
     * as a reward for DEX stakers.
     *
     * Emits a {Sweep} event indicating the amount of tokens that
     * were swept.
     *
     * Requirements:
     *
     * - the airdrop must have ended
     * - the caller must be the team
     * - the contract must have leftover tokens
     */
    function sweep(uint256 biopPerBlock) external {
        require(block.timestamp > end, "VXAirdrop::sweep: Swap active");
        require(
            msg.sender == team,
            "VXAirdrop::sweep: Insufficient Priviledges"
        );

        uint256 leftovers = biopV5.balanceOf(address(this));

        require(leftovers != 0, "VXAirdrop::sweep: Nothing to sweep");

        emit Sweep(leftovers);

        biopV5.approve(address(dexRewards), leftovers);
        dexRewards.fund(leftovers, biopPerBlock);
    }
}
