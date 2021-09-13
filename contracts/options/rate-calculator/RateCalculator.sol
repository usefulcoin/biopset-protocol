// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/options/rate-calculator/IRateCalculator.sol";

/**
 * @dev Implementation of the {IRateCalculator} interface.
 *
 * Implements the core principle of a {RateCalculator} that more advanced
 * rate calculators can inherit from to apply custom payout calculations.
 */
abstract contract RateCalculator is IRateCalculator, ProtocolConstants {
    using SafeMath for uint256;

    /* ========== VIEWS ========== */

    /**
     * @dev Calculates the rate a particular option should be awarded with,
     * applying multiple protocol-level validations to the original amount as
     * well as the one to be awarded.
     *
     * Requirements:
     *
     * - the payout must be below the maximum option size
     * - the new locked total must not exceed the maximum pool utilization threshold
     */
    function calculateRate(
        uint256 poolBalance,
        uint256 openCalls,
        uint256 openPuts,
        uint256 amount,
        uint256 rounds,
        bool isCall,
        uint256 eth
    ) external view override returns (uint256) {
        poolBalance = poolBalance.sub(eth);
        uint256 poolUtilization = openCalls.add(openPuts);

        uint256 maximumLockOrPayout = poolBalance.mul(_MAX_OPTION_SIZE).div(
            _MAX_BASIS_POINTS
        );

        uint256 maximumLock;
        if (openCalls == openPuts) maximumLock = maximumLockOrPayout;
        else if (isCall)
            maximumLock = maximumLockOrPayout.add(openPuts).sub(openCalls);
        else maximumLock = maximumLockOrPayout.add(openCalls).sub(openPuts);

        // Basic Rate Payout is 2x
        uint256 payout = _getPayout(amount, rounds);

        require(
            payout <= poolBalance.mul(_MAX_OPTION_SIZE).div(_MAX_BASIS_POINTS),
            "RateCalculator::calculateRate: Option Payout Exceeds Maximum"
        );

        payout = amount.add(payout);

        require(
            poolUtilization.add(payout) <=
                poolBalance.mul(_MAX_UTILIZATION).div(_MAX_BASIS_POINTS),
            "RateCalculator::calculateRate: Pool Utilization Exceeds Maximum"
        );

        return payout;
    }

    /**
     * @dev Calculates the maximum multiplier the calculator can yield. Used to ensure
     * that the pool will be able to satisfy the call's payout regardless of other
     * system parameters.
     */
    function calculateMaxMultiplier() external view override returns (uint256) {
        return _maxMultiplier();
    }

    /**
     * @dev See implementations.
     */
    function _getPayout(uint256 amount, uint256 rounds)
        internal
        view
        virtual
        returns (uint256);

    /**
     * @dev See implementations.
     */
    function _maxMultiplier() internal view virtual returns (uint256);
}
