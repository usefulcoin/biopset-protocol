// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../external/chainlink/IAggregatorV3.sol";

interface IBIOPOracle {
    /* ========== FUNCTIONS ========== */

    function chainlinkOracle(IERC20 token)
        external
        view
        returns (IAggregatorV3);

    function roundTolerance() external view returns (uint256);

    function getEtherPrice() external view returns (uint256);

    function getPrice(IERC20 token)
        external
        view
        returns (uint80 round, uint256 price);

    function getPrice(IERC20 token, uint80 round)
        external
        view
        returns (uint256);

    function updateSource(IERC20 token, IAggregatorV3 source) external;

    function updateTolerance(uint256 _roundTolerance) external;

    /* ========== EVENTS ========== */

    event OracleChanged(
        IERC20 token,
        IAggregatorV3 previous,
        IAggregatorV3 next
    );

    event ToleranceChanged(uint256 previous, uint256 next);
}
