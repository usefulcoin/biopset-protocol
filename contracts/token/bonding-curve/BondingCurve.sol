// SPDX-License-Identifier: MIT

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./BancorFormula.sol";

import "../../shared/ProtocolConstants.sol";

/**
 * @dev Implementation of a basic bonding curve using the Bancor formula.
 *
 * Wraps around the Bancor Formula implementation to expose its functions
 * under different aliases.
 */
abstract contract BondingCurve is BancorFormula {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // The BIOP token
    IERC20 public immutable biop;

    /**
     * The reserve ratio is represented in PPM [1-1000000] with some indicative values below:
     *
     * - 1/3 corresponds to y = multiple * x^2
     * - 1/2 corresponds to y = multiple * x
     * - 2/3 corresponds to y = multiple * x^1/2
     */
    uint32 public immutable reserveRatio;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {biop} and the {reserveRatio}.
     *
     * It validates that the {biop} is non-zero and that the {reserveRatio} is
     * within the thresholds expected by Bancor. The {reserveRatio} is expected
     * to have been carefully and properly selected by the creator of the contract.
     */
    constructor(IERC20 _biop, uint32 _reserveRatio) public {
        require(
            _biop != IERC20(0),
            "BondingCurve::constructor: Misconfiguration"
        );
        require(
            _reserveRatio >= _MIN_RESERVE_RATIO &&
                _reserveRatio <= _MAX_RESERVE_RATIO,
            "BondingCurve::constructor: Incorrect Reserve Ratio"
        );

        biop = _biop;
        reserveRatio = _reserveRatio;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the amount of tokens that should be provided for a particular
     * purchase operation (mint). Factors in the currently deposited msg.value that
     * should be subtracted from the balance that is fed to the Bancor formula.
     */
    function calculateMint(uint256 amount) public view returns (uint256) {
        return
            calculatePurchaseReturn(
                continuousSupply(),
                reserveBalance().sub(amount),
                reserveRatio,
                amount
            );
    }

    /**
     * @dev Returns the amount of native asset tokens that should be provided for
     * a particular sale operation (burn).
     */
    function calculateBurn(uint256 amount) public view returns (uint256) {
        return
            calculateSaleReturn(
                continuousSupply(),
                reserveBalance(),
                reserveRatio,
                amount
            );
    }

    /* ========== VIRTUAL ========== */

    /**
     * @dev See implementation.
     */
    function continuousSupply() public view virtual returns (uint256);

    /**
     * @dev See implementation.
     */
    function reserveBalance() public view virtual returns (uint256);
}
