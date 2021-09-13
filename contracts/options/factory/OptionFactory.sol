// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../Option.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/options/factory/IOptionFactory.sol";

/**
 * @dev Implementation of the {IOptionFactory} interface.
 *
 * Allows options to be generated for different tokens and assigns
 * some basic values to them.
 */
contract OptionFactory is IOptionFactory, ProtocolConstants, Ownable {
    /* ========== STATE VARIABLES ========== */

    // The BIOP oracle used for option pricing
    IBIOPOracle public immutable oracle;

    // The BIOP utilization reward contract tracking utilization rewards
    IUtilizationRewards public immutable utilization;

    // The BIOP treasury used to send fees
    address payable public immutable treasury;

    // Indicates whether an address is an option
    mapping(address => bool) public override isOption;

    // Indicates whether a token has an option defined
    mapping(IERC20 => IOption) public override option;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {oracle}, {utilization}, {treasury}, and transfers
     * ownership of the contract to the DAO.
     *
     * Simple validation is applied to all arguments and the ownership system is utilized
     * to ensure only the DAO is able to create option contracts in the BIOP system.
     */
    constructor(
        IBIOPOracle _oracle,
        IUtilizationRewards _utilization,
        address payable _treasury,
        address _dao
    ) public {
        require(
            _oracle != IBIOPOracle(0) &&
                _utilization != IUtilizationRewards(0) &&
                _treasury != address(0) &&
                _dao != address(0),
            "OptionFactory::constructor: Misconfiguration"
        );

        oracle = _oracle;
        utilization = _utilization;
        treasury = _treasury;

        transferOwnership(_dao);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows an option to be newly created for a particular token.
     *
     * Emits an {OptionCreated} event indicating the address of the option.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - an option must not have been previously created for the specified token
     */
    function createOption(ERC20 token)
        external
        override
        onlyOwner
        returns (IOption)
    {
        require(
            option[token] == IOption(0),
            "OptionFactory::createOption: Option Already Exists"
        );

        IOption creation = new Option(
            token,
            oracle,
            utilization,
            treasury,
            msg.sender
        );
        option[token] = creation;
        isOption[address(creation)] = true;

        emit OptionCreated(token, creation);
    }
}
