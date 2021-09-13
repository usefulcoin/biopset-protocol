// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./pool/Pool.sol";

import "../interfaces/options/IOption.sol";
import "../interfaces/oracle/IBIOPOracle.sol";

/**
 * @dev Implementation of the {IOption} interface.
 *
 * This contract allows call and put options to be opened against
 * a particular asset and acts as the core component of the BIOP protocol,
 * allowing users to supply capital for the options to be fulfilled.
 */
contract Option is IOption, Pool {
    /* ========== STATE VARIABLES ========== */

    // The BIOP oracle consulted for the options
    IBIOPOracle public immutable oracle;

    // The rate calculator responsible for calculating the ITM values of the options
    IRateCalculator public calculator;

    // The minimum and maximum round thresholds for options
    uint256 public minRounds;
    uint256 public maxRounds;

    // The protocol fee applied to successful options
    uint256 public protocolFee;

    // Whether gas costs should be rewarded with BIOP tokens to offset their cost
    bool public gasRefund;

    // The list of all binary options in the BIOP system
    BinaryOption[] public options;

    // The amount of tokens locked in open calls
    uint256 public openCalls;

    // The amount of tokens locked in open puts
    uint256 public openPuts;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initializes the {Pool} implementation and the value of {oracle}.
     *
     * The constructor validates that the oracle address has been strictly set.
     */
    constructor(
        ERC20 _token,
        IBIOPOracle _oracle,
        IUtilizationRewards _utilization,
        address payable _treasury,
        address _dao
    ) public Pool(_token, _utilization, _treasury, _dao) {
        require(
            _oracle != IBIOPOracle(0),
            "Option::constructor: Misconfiguration"
        );

        oracle = _oracle;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the maximum multiplier of an option as calculated by the {RateCalculator}
     */
    function maxMultiplier() public view returns (uint256) {
        return calculator.calculateMaxMultiplier();
    }

    /**
     * @dev Returns the reward rate of a particular call option
     */
    function getCallRate(uint256 amount, uint256 rounds)
        external
        view
        returns (uint256)
    {
        return _getRate(amount, rounds, true, 0);
    }

    /**
     * @dev Returns the reward rate of a particular put option
     */
    function getPutRate(uint256 amount, uint256 rounds)
        external
        view
        returns (uint256)
    {
        return _getRate(amount, rounds, false, 0);
    }

    /**
     * @dev Returns the total number of options
     */
    function totalOptions() external view returns (uint256) {
        return options.length;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a call option to be opened. For more, see {_open}.
     */
    function openCall(uint256 amount, uint80 rounds)
        external
        payable
        rewardGas
    {
        _open(true, amount, rounds);
    }

    /**
     * @dev Allows a put option to be opened. For more, see {_open}.
     */
    function openPut(uint256 amount, uint80 rounds) external payable rewardGas {
        _open(false, amount, rounds);
    }

    /**
     * @dev Allows the fulfillment of an option by any party, either rewarding the
     * option's creator or liquidating their position distributing it to the pool's
     * stakers.
     *
     * Requirements:
     *
     * - the option must not have already been evaluated
     */
    function complete(uint256 id) external rewardGas {
        BinaryOption storage option = options[id];

        require(!option.evaluated, "Option::exercise: Already Exercised");

        option.evaluated = true;

        uint256 price = oracle.getPrice(token, option.expiration);

        uint256 _reward = option.reward;
        if (option.call) {
            // NOTE: Call Option -> Strike > Price [Expire] || Strike <= Price [Exercise]
            if (option.strikePrice > price) {
                _expire(id, _reward);
            } else {
                _exercise(id, option.beneficiary, _reward);
            }
            openCalls = openCalls.sub(_reward);
        } else {
            // NOTE: Put Option -> Price > Strike [Expire] || Price <= Strike [Exercise]
            if (price > option.strikePrice) {
                _expire(id, _reward);
            } else {
                _exercise(id, option.beneficiary, _reward);
            }
            openPuts = openPuts.sub(_reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows the DAO to update the maximum rounds an option can be opened for.
     *
     * Emits a {MaximumRoundChanged} event indicating the previous and new maximum.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the new maximum must be greater than or equal to the current minimum
     */
    function updateMaximumRounds(uint256 _maxRounds)
        external
        override
        onlyOwner
    {
        require(
            _maxRounds >= minRounds,
            "Option::updateMaximumRounds: Max Round Must Be Greater Than Min Round"
        );

        emit MaximumRoundChanged(maxRounds, _maxRounds);

        maxRounds = _maxRounds;
    }

    /**
     * @dev Allows the DAO to update the minimum rounds an option can be opened for.
     *
     * Emits a {MinimumRoundChanged} event indicating the previous and new minimum.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the new minimum must be greater than or equal to the system minimum of the oracle
     */
    function updateMinimumRounds(uint256 _minRounds)
        external
        override
        onlyOwner
    {
        require(
            _minRounds >= oracle.roundTolerance(),
            "Option::updateMinimumRounds: Incorrect Minimum Round Time"
        );

        emit MinimumRoundChanged(minRounds, _minRounds);

        minRounds = _minRounds;
    }

    /**
     * @dev Allows the DAO to set whether gas should be refunded in the form of BIOP rewards.
     *
     * Emits a {GasRewardStatus} event indicating the new status.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function setGasRewardStatus(bool _gasRefund) external override onlyOwner {
        emit GasRewardStatus(_gasRefund);

        gasRefund = _gasRefund;
    }

    /**
     * @dev Allows the DAO to change the protocol fee imposed on successful options.
     *
     * Emits a {ProtocolFeeChanged} event indicating the previous and new protocol fees.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function updateProtocolFee(uint256 _protocolFee)
        external
        override
        onlyOwner
    {
        emit ProtocolFeeChanged(protocolFee, _protocolFee);

        protocolFee = _protocolFee;
    }

    /**
     * @dev Allows the DAO to change the rate calculator used for assessing option rewards.
     *
     * Emits a {CalculatorChanged} event indicating the previous and new rate calculators.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the new calculator must be strictly set
     */
    function updateRater(IRateCalculator _calculator)
        external
        override
        onlyOwner
    {
        require(
            _calculator != IRateCalculator(0),
            "Option::updateRater: Calculator Cannot Be Unset"
        );

        emit CalculatorChanged(calculator, _calculator);

        calculator = _calculator;
    }

    /**
     * @dev Deactivates the option, preventing new options from being opened.
     *
     * Emits a {StatusChanged} event indicating the previous and new statuses.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function deactivateOption() external override onlyOwner {
        emit StatusChanged(status, Status.INACTIVE);

        status = Status.INACTIVE;
    }

    /**
     * @dev Freezes the option, preventing new deposits to its liquidity pool.
     *
     * Emits a {StatusChanged} event indicating the previous and new statuses.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function freezeOption() external override onlyOwner {
        emit StatusChanged(status, Status.FROZEN);

        status = Status.FROZEN;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Retrieves the reward rate of a particular option from the rate calculator
     */
    function _getRate(
        uint256 amount,
        uint256 rounds,
        bool isCall,
        uint256 eth
    ) private view returns (uint256) {
        return
            calculator.calculateRate(
                balance(),
                openCalls,
                openPuts,
                amount,
                rounds,
                isCall,
                eth
            );
    }

    /**
     * @dev Exercises a particular option, awarding it with its locked value.
     *
     * If an option is exercised by someone else other than the beneficiary, a
     * settler fee is imposed and transferred to them to incentivize options to
     * be settled.
     *
     * Emits an {Exercised} event indicating the ID of the option exercised.
     */
    function _exercise(
        uint256 id,
        address payable beneficiary,
        uint256 amount
    ) private {
        _unlock(amount);

        uint256 fee = amount.mul(protocolFee).div(_MAX_BASIS_POINTS);
        if (fee != 0) _send(treasury, fee);

        amount -= fee;

        if (msg.sender != beneficiary) {
            fee = amount.mul(settlerFee).div(_MAX_BASIS_POINTS);
            if (fee != 0) _send(msg.sender, fee);
            amount -= fee;
        }

        _send(beneficiary, amount);

        emit Exercised(id);
    }

    /**
     * @dev Expires a particular option, liquidating it to all pool shareholders.
     *
     * A settler fee is imposed and transferred to the expirer of the option regardless
     * of whether they are the original beneficiary or not.
     *
     * Emits an {Expired} event indicating the ID of the option exercised.
     */
    function _expire(uint256 id, uint256 amount) private {
        _unlock(amount);

        uint256 fee = amount.mul(settlerFee).div(_MAX_BASIS_POINTS);
        if (fee != 0) _send(msg.sender, fee);

        emit Expired(id);
    }

    /**
     * @dev Opens an option of the specified type.
     *
     * Emits either a {CallOption} or {PutOption} event indicating the attributes of the option.
     *
     * Requirements:
     *
     * - the status of the contract must be active
     * - the rounds the option is expiring in must be within the
     * system's thresholds
     * - the token the option is opened for must have an oracle defined
     * - the size of the option must be satisfiable
     */
    function _open(
        bool isCall,
        uint256 amount,
        uint80 rounds
    ) private {
        require(
            status == Status.ACTIVE,
            "Option::_open: Option Opening Disabled"
        );

        require(
            minRounds <= rounds && rounds <= maxRounds,
            "Option::_open: Invalid Rounds"
        );
        require(
            oracle.chainlinkOracle(token) != IAggregatorV3(0),
            "Option::_open: Unsupported Token"
        );

        amount = _validateAmount(amount);

        // NOTE: Current size includes pending deposit
        require(
            amount <= available().sub(msg.value).div(maxMultiplier()),
            "Option::_open: Option Too Large"
        );

        (uint80 round, uint256 price) = oracle.getPrice(token);

        uint256 reward = _getRate(amount, rounds, isCall, msg.value);

        uint256 expiration = uint256(round).add(rounds);

        // NOTE: Should never happen
        assert(expiration <= type(uint80).max);

        options.push(
            BinaryOption({
                beneficiary: msg.sender,
                strikePrice: price,
                amount: amount,
                reward: reward,
                expiration: uint80(expiration),
                call: isCall,
                evaluated: false
            })
        );
        _lock(reward);

        if (isCall) {
            openCalls = openCalls.add(reward);
            emit CallOption(msg.sender, price, amount, reward, expiration);
        } else {
            openPuts = openPuts.add(reward);
            emit PutOption(msg.sender, price, amount, reward, expiration);
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev Calculates and rewards gas usage to the utilization reward contract if enabled
     */
    modifier rewardGas() {
        if (gasRefund) {
            uint256 gas = gasleft();
            _;
            // NOTE: Guaranteed to not overflow due to EVM constraints
            utilization.trackGas((gas - gasleft()) * tx.gasprice);
        } else _;
    }
}
