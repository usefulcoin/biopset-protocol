// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../shared/ProtocolConstants.sol";

import "../interfaces/staking/IDAOStaking.sol";
import "../interfaces/treasury/ITreasury.sol";

/**
 * @dev Implementation of the {ITreasury} interface.
 *
 * Treasury implementation of the BIOP V5 system. It allows the DAO to transfer
 * the funds it holds outwards in either native or token form. A configurable
 * tax is applied on native outgoing transactions that is re-directed to the BIOP
 * stakers as a reward.
 */
contract Treasury is ITreasury, ProtocolConstants, Ownable {
    using SafeMath for uint256;
    using Address for address payable;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // The BIOP staking implementation for distributing tax
    IDAOStaking public immutable staking;

    // The tax to apply on each transaction
    uint256 public tax = _INITIAL_TREASURY_TAX;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the value for {staking} and transfers ownership of the contract
     * to the {_dao}.
     *
     * It applies rudimentary input sanitization by ensuring both addresses are
     * defined.
     */
    constructor(IDAOStaking _staking, address _dao) public {
        require(
            _staking != IDAOStaking(0) && _dao != address(0),
            "Treasury::constructor: Misconfiguration"
        );

        staking = _staking;
        transferOwnership(_dao);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows an outward transfer of the asset and amount specified.
     *
     * Emits a {TokenTransfer} or {NativeTransfer} event indicating the amount transferred,
     * the intended recipient as well as the fee if applicable.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     * - the contract must hold sufficient balance to fulfill the transaction
     */
    function send(
        IERC20 token,
        address payable destination,
        uint256 amount
    ) external override onlyOwner {
        if (token == IERC20(_ETHER)) {
            uint256 _tax = amount.mul(tax).div(_MAX_BASIS_POINTS);

            if (_tax != 0) {
                staking.notifyRewardAmount{value: _tax}();
                amount -= _tax;
            }

            emit NativeTransfer(destination, amount, _tax);

            destination.sendValue(amount);
        } else {
            emit TokenTransfer(address(token), destination, amount);

            token.safeTransfer(destination, amount);
        }
    }

    /**
     * @dev Allows the tax applied to native transfers to be configured.
     *
     * Emits a {TaxChanged} event indicating the previous and new tax values.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function updateTax(uint256 _tax) external override onlyOwner {
        emit TaxChanged(tax, _tax);

        tax = _tax;
    }

    /* ========== NATIVE FUNCTIONS ========== */

    /**
     * @dev Allows the contract to receive native asset transfers.
     *
     * Emits a {Funding} event indicating the amount received as well as who transferred it.
     */
    receive() external payable {
        emit Funding(msg.sender, msg.value);
    }
}
