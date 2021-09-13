// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./pool/IPool.sol";
import "./rate-calculator/IRateCalculator.sol";

interface IOption is IPool {
    /* ========== STRUCTS ========== */

    struct BinaryOption {
        address payable beneficiary; // Beneficiary of Option
        uint256 strikePrice; // Strike Price
        uint256 amount; // Purchase Value
        uint256 reward; // In-The-Money Value (lockedValue)
        uint80 expiration; // Expiration Round
        bool call; // Indicates if Call / Put
        bool evaluated; // Indicates if evaluated
    }

    /* ========== FUNCTIONS ========== */

    function updateMaximumRounds(uint256 _maxRounds) external;

    function updateMinimumRounds(uint256 _minRounds) external;

    function setGasRewardStatus(bool status) external;

    function updateProtocolFee(uint256 fee) external;

    function updateRater(IRateCalculator calculator) external;

    function deactivateOption() external;

    function freezeOption() external;

    /* ========== EVENTS ========== */

    event Expired(uint256 id);
    event Exercised(uint256 id);
    event MaximumRoundChanged(uint256 previous, uint256 next);
    event MinimumRoundChanged(uint256 previous, uint256 next);
    event GasRewardStatus(bool enabled);
    event ProtocolFeeChanged(uint256 previous, uint256 next);
    event CalculatorChanged(IRateCalculator previous, IRateCalculator next);
    event CallOption(
        address indexed beneficiary,
        uint256 price,
        uint256 amount,
        uint256 reward,
        uint256 expiration
    );
    event PutOption(
        address indexed beneficiary,
        uint256 price,
        uint256 amount,
        uint256 reward,
        uint256 expiration
    );
}
