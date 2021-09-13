// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../shared/ProtocolConstants.sol";

import "../interfaces/token/IBIOP.sol";
import "../interfaces/options/utilization/IUtilizationRewards.sol";
import "../interfaces/token/vesting/IVesting.sol";
import "../interfaces/token/ibco/ITieredICO.sol";
import "../interfaces/token/dex-rewards/IDEXRewards.sol";
import "../interfaces/token/legacy-swap/IVXSwap.sol";
import "../interfaces/token/legacy-airdrop/IVXAirdrop.sol";

/**
 * @dev Implementation of the BIOP v5 token.
 *
 * The implementation is a typical EIP-20 token that contains a
 * novel {initialize} hook meant to be invoked when all system
 * components have been deployed.
 *
 * When invoked, it mints the total supply of the BIOP dispersed
 * among the various modules and initializes each one by invoking
 * the corresponding initialization hook on them.
 */
contract BIOP is IBIOP, ERC20, ProtocolConstants, Ownable {
    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initializes the OpenZeppelin ERC20 implementation with the corresponding
     * token name and symbol.
     */
    constructor()
        public
        ERC20("Binary Options Settlement Protocol", "BIOPv5")
    {}

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Initializes the Binary Options Settlement Protocol v5.
     *
     * Emits an {Initialized} event indicating all system component addresses.
     *
     * Requirements:
     *
     * - the caller must be the owner of the contract
     * - all addresses must be strictly defined
     */
    function initialize(
        IVesting _vest,
        IVXSwap _swap,
        IVXAirdrop _airdrop,
        IUtilizationRewards _utilization,
        ITieredICO _ico,
        address _amm,
        IDEXRewards _dexRewards,
        uint256 _dexBiopPerBlock
    ) external onlyOwner {
        require(
            _vest != IVesting(0) &&
                _swap != IVXSwap(0) &&
                _airdrop != IVXAirdrop(0) &&
                _utilization != IUtilizationRewards(0) &&
                _ico != ITieredICO(0) &&
                _amm != address(0) &&
                _dexRewards != IDEXRewards(0),
            "BIOP::initialize: Misconfiguration"
        );

        _mint(address(_vest), _DEV_ALLOCATION);
        _vest.startVesting();

        _mint(address(_swap), _SWAP_ALLOCATION);
        _swap.startSwap();

        _mint(address(_airdrop), _AIRDROP_ALLOCATION);
        _airdrop.startAirdrop();

        // NOTE: Actuated Automatically
        _mint(address(_utilization), _UTILIZATION_ALLOCATION);

        _mint(address(_ico), _ICO_ALLOCATION);
        _ico.startSale();

        _mint(address(this), _DEX_ALLOCATION);
        _approve(address(this), address(_dexRewards), _DEX_ALLOCATION);
        _dexRewards.fund(_DEX_ALLOCATION, _dexBiopPerBlock);

        // NOTE: Actuated Later
        _mint(address(_amm), _AMM_ALLOCATION);

        emit Initialized(
            address(_vest),
            address(_swap),
            address(_utilization),
            address(_ico),
            address(_amm),
            address(_dexRewards)
        );

        renounceOwnership();
    }
}
