// SPDX-License-Identifier: MIT

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./BondingCurve.sol";

import "../../interfaces/token/bonding-curve/IBondingCurveAMM.sol";

/**
 * @dev Implementation of the {IBondingCurveAMM} interface.
 *
 * A Bancor based bonding curve AMM with a configurable sale and buy fee
 * meant to be initialized with a set native asset supply beyond deployment.
 *
 * Care should be applied with regards to the amount of native asset funds
 * the AMM is supplied with as a value that does not match market conditions
 * will create an arbitrage opportunity between the bonding curve AMM and
 * the traditional AMMs.
 */
contract BondingCurveAMM is
    BondingCurve,
    IBondingCurveAMM,
    Ownable,
    ReentrancyGuard
{
    using Address for address payable;

    /* ========== STATE VARIABLES ========== */

    // The address fees should go to
    address payable public immutable treasury;

    // Total tokens sold
    uint256 public totalSold;

    // Purchase fee applied to the native asset before conversion
    uint256 public buyFee;

    // Sell fee applied to the native asset after conversion
    uint256 public sellFee;

    // Indicates whether the AMM is active
    bool public active;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {treasury} and invokes the {BondingCurve} lifecycle hook.
     *
     * Performs basic sanitization to ensure the treasury address has been validly defined.
     */
    constructor(
        IERC20 _biop,
        address payable _treasury,
        uint32 _reserveRatio
    ) public BondingCurve(_biop, _reserveRatio) {
        require(
            _treasury != address(0),
            "BondingCurveAMM::constructor: Misconfiguration"
        );

        treasury = _treasury;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the amount of tokens sold.
     */
    function continuousSupply() public view override returns (uint256) {
        return totalSold;
    }

    /**
     * @dev Returns the amount of native funds that are deposited to the curve.
     */
    function reserveBalance() public view override returns (uint256) {
        return address(this).balance;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to make a purchase on the bonding curve.
     *
     * Emits a {Purchase} event indicating the amount deposited and
     * amount purchased, including any fee sent to the treasury.
     *
     * Requirements:
     *
     * - the amount provided for the purchase must be non-zero
     */
    function buy() external payable nonReentrant {
        require(
            msg.value != 0,
            "BondingCurveAMM::buy: Non-Zero Amount Required"
        );

        uint256 purchase = msg.value;

        uint256 fee;
        if (buyFee != 0) {
            fee = purchase.mul(buyFee).div(_MAX_BASIS_POINTS);
            treasury.sendValue(fee);
            purchase -= fee;
        }

        uint256 amount = calculateMint(purchase);

        totalSold = totalSold.add(amount);

        emit Purchase(msg.sender, purchase, amount, fee);

        biop.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Allows a user to sell their tokens on the curve.
     *
     * Emits a {Sale} event indicating the amount sold and
     * amount of native asset received in return, including any fee
     * sent to the treasury.
     *
     * Requirements:
     *
     * - the amount provided for the sale must be non-zero
     */
    function sell(uint256 amount) external nonReentrant returns (uint256) {
        require(amount != 0, "BondingCurveAMM::sell: Non-Zero Amount Required");

        uint256 eth = calculateBurn(amount);

        uint256 fee;
        if (sellFee != 0) {
            fee = eth.mul(sellFee).div(_MAX_BASIS_POINTS);
            treasury.sendValue(fee);
            eth -= fee;
        }

        totalSold = totalSold.sub(amount);

        emit Sale(msg.sender, amount, eth, fee);

        biop.safeTransferFrom(msg.sender, address(this), amount);
        msg.sender.sendValue(amount);

        return eth;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows the AMM to be initialized by the BIOP team.
     *
     * Emits a {Reserves} event indicating the newly set reserves.
     *
     * Requirements:
     *
     * - the caller must be the BIOP team
     */
    function initialize(uint256 initialSoldSupply) external payable onlyOwner {
        active = true;

        totalSold = initialSoldSupply;

        emit Reserves(
            msg.value,
            biop.balanceOf(address(this)),
            initialSoldSupply
        );

        renounceOwnership();
    }
}
