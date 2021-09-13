// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../IOption.sol";

interface IOptionFactory {
    /* ========== FUNCTIONS ========== */

    function isOption(address option) external view returns (bool);

    function option(IERC20 token) external view returns (IOption);

    function createOption(ERC20 token) external returns (IOption);

    /* ========== EVENTS ========== */

    event OptionCreated(IERC20 token, IOption creation);
}
