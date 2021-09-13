// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../shared/ProtocolConstants.sol";

import "../../interfaces/oracle/IBIOPOracle.sol";
import "../../interfaces/token/ibco/ITieredICO.sol";

/**
 * @dev Implementation of the {ITieredICO} interface.
 *
 * A tiered ICO implementation that automatically escalates the
 * current price of the ICO based on the amount of tokens that have
 * been purchased.
 *
 * Each tier is specfieid in terms of the allocation it is meant to hold,
 * the USD price that it should go for and the amount of native tokens that
 * equate that USD price.
 *
 * The last part is calculated automatically the moment the sale is set as active
 * by querying the BIOP oracle system.
 */
contract TieredICO is ITieredICO, ProtocolConstants, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;

    /* ========== STATE VARIABLES ========== */

    // The Token
    IERC20 public immutable biop;

    // Beneficiary of sale
    address public immutable beneficiary;

    // The BiOpSet oracle
    IBIOPOracle public immutable oracle;

    // The configuration of each tier
    Tier[_ICO_TIERS] public tiers;

    // Total tokens sold
    uint256 public totalSold;

    // Sale Start & End
    uint256 public start;
    uint256 public end;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for {biop}, {oracle}, {beneficiary}, and
     * {tiers}. Additionally transfers ownership of the contract to
     * the BIOP token.
     *
     * Allocations are expected to be sequential and so are prices.
     * Additionally, USD prices are expected to be expressed using 8
     * decimals of precision similarly to the Chainlink oracle system.
     */
    constructor(
        IERC20 _biop,
        IBIOPOracle _oracle,
        uint256[_ICO_TIERS] memory tierAllocations,
        uint256[_ICO_TIERS] memory desiredPricesUSD
    ) public {
        require(
            _biop != IERC20(0) && _oracle != IBIOPOracle(0),
            "TieredICO::constructor: Misconfiguration"
        );

        biop = _biop;
        oracle = _oracle;
        beneficiary = msg.sender;

        uint256 previousPrice;
        uint256 previousAllocation;
        for (uint256 i = 0; i < _ICO_TIERS; i++) {
            uint256 usdPrice = desiredPricesUSD[i];

            require(
                usdPrice > previousPrice,
                "TieredICO::constructor: Incorrect Tier Price Specified"
            );

            uint256 allocation = tierAllocations[i];

            require(
                allocation > previousAllocation,
                "TieredICO::constructor: Incorrect Tier Allocation"
            );

            tiers[i].usdPrice = previousPrice = usdPrice;
            tiers[i].allocation = previousAllocation = allocation;
        }

        transferOwnership(address(_biop));
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the amount of tokens an investment
     * will result in.
     */
    function calculateTokens(uint256 investment)
        external
        view
        returns (uint256 tokens)
    {
        (tokens, ) = _calculateTokens(investment);
    }

    /**
     * @dev Returns the currently active tier of the sale.
     */
    function currentTier() external view returns (uint256, uint256) {
        return _currentTier(totalSold);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to invest in the tiered ICO.
     */
    function invest() external payable {
        _invest(msg.value);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Initializes the ICO by starting it beyond the grace period. Additionally,
     * calculates the actual prices of the ICO tiers by using the spot price of the
     * native asset via the BIOP oracle.
     *
     * Emits an {Initialized} event indicating the start and end of the ICO as well as
     * {TierSet} events for each tier of the ICO indicating its data.
     *
     * Requirements:
     *
     * - the caller must be the BIOP token
     */
    function startSale() external override onlyOwner {
        uint256 _start;
        uint256 _end;
        start = _start = block.timestamp + _GRACE_PERIOD;
        end = _end = block.timestamp + _GRACE_PERIOD + _ICO_DURATION;

        emit Initialized(_start, _end);

        uint256 etherPrice = oracle.getEtherPrice();

        for (uint256 i = 0; i < _ICO_TIERS; i++) {
            Tier memory tier = tiers[i];
            uint256 tierPrice = tier.usdPrice.mul(1 ether).div(etherPrice);

            emit TierSet(i, tier.allocation, tier.usdPrice, tierPrice);

            tier.etherPrice = tierPrice;
            tiers[i] = tier;
        }

        renounceOwnership();
    }

    /**
     * @dev Allows the beneficiary of the ICO sale to claim the raised funds.
     *
     * Emits a {Collect} event indicating the amount of funds that were claimed
     * as well as any leftover BIOP tokens in the contract that were refunded to
     * the beneficiary.
     *
     * Requirements:
     *
     * - the caller must be the beneficiary
     * - the sale must have ended
     */
    function collect() external {
        require(
            msg.sender == beneficiary,
            "TieredICO::collect: Insufficient Privileges"
        );
        require(
            block.timestamp > end && start != 0,
            "TieredICO::collect: ICO Active"
        );

        uint256 leftovers = biop.balanceOf(address(this));
        uint256 raisedFunds = address(this).balance;

        emit Collect(raisedFunds, leftovers);

        msg.sender.sendValue(raisedFunds);

        if (leftovers != 0) biop.safeTransfer(msg.sender, leftovers);
    }

    /* ========== NATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to invest in the ICO natively via a direct native asset transfer.
     */
    receive() external payable {
        _invest(msg.value);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Calculates the amount of tokens a particular investment is due. Accurately
     * calculates the amount by iterating through the tiers should a single investment
     * cause a tier to change.
     */
    function _calculateTokens(uint256 investment)
        private
        view
        returns (uint256 total, uint256 refund)
    {
        uint256 tokensSold = totalSold;
        while (investment != 0) {
            (uint256 price, uint256 tokensRemaining) = _currentTier(tokensSold);

            // NOTE: This means that no more tokens are available for sale
            if (price == 0) return (0, investment);

            uint256 investmentTokens = investment / price;

            if (investmentTokens > tokensRemaining) {
                total = total.add(tokensRemaining);

                investment = investment.sub(tokensRemaining.mul(price));
                tokensSold = tokensSold.add(tokensRemaining);
            } else {
                total = total.add(investmentTokens);
                refund = investment.sub(investmentTokens.mul(price));
                break;
            }
        }
    }

    /**
     * @dev Assess the current tier and returns the tier's price as well
     * as remaining amount to advance to the next one.
     */
    function _currentTier(uint256 tokensSold)
        private
        view
        returns (uint256, uint256)
    {
        for (uint256 i = 0; i < _ICO_TIERS; i++) {
            Tier storage tier = tiers[i];
            uint256 allocation = tier.allocation;
            if (allocation > tokensSold)
                return (tier.etherPrice, allocation - tokensSold);
        }
    }

    /**
     * @dev Invests the specified amount to the ICO.
     *
     * Emits an {Investment} event indicating the amount of funds the user invested
     * and amount of tokens they got in return.
     *
     * Requirements:
     *
     * - the sale must be active
     * - the amount invested must be non-zero
     */
    function _invest(uint256 amount) private {
        require(block.timestamp <= end, "TieredICO::invest: Sale Inactive");
        require(amount != 0, "TieredICO::invest: Non-Zero Investment Required");

        (uint256 tokens, uint256 refund) = _calculateTokens(amount);

        emit Investment(amount.sub(refund), tokens);

        if (tokens != 0) {
            totalSold = totalSold.add(tokens);
            biop.safeTransfer(msg.sender, tokens);
        }
        if (refund != 0) msg.sender.sendValue(refund);
    }
}
