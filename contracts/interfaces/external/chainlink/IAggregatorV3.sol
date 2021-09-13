// SPDX-License-Identifier: MIT

pragma solidity =0.6.8;

interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    // latestRoundData should raise a "No data present" error
    // if it does not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
