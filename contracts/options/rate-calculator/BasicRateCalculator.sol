// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./RateCalculator.sol";

/**
 * @dev A basic rate calculator implementation that applies a fixed multiplier to
 * the reward of an option.
 */
contract BasicRateCalculator is RateCalculator {
    /**
     * @dev Multiplies the original option amount by the basic calculator's multiplier
     */
    function _getPayout(uint256 amount, uint256)
        internal
        view
        override
        returns (uint256)
    {
        return amount.mul(_BASIC_PAYOUT_MULTIPLIER);
    }

    /**
     * @dev Yields the basic calculator's multiplier
     */
    function _maxMultiplier() internal view override returns (uint256) {
        return _BASIC_PAYOUT_MULTIPLIER;
    }
}
