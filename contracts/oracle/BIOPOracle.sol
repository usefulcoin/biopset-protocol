// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../shared/ProtocolConstants.sol";

import "../interfaces/oracle/IBIOPOracle.sol";

/**
 * @dev Implementation of the {IBIOPOracle} interface.
 *
 * The BIOP oracle implementation that aggregates multiple
 * Chainlink price nodes under it to support multiple EIP-20
 * and native asset tokens within the BIOP system.
 *
 * Contains a built-in round threshold mechanism for the initially
 * reported price (as used by options) to ensure it is valid. The
 * same validation is not applied to an option expiring as an unreported
 * value between opening and closing should not occur and needs to be accepted
 * as valid.
 */
contract BIOPOracle is IBIOPOracle, ProtocolConstants, Ownable {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // Oracle Per Token
    mapping(IERC20 => IAggregatorV3) public override chainlinkOracle;

    // Staleness Tolerance
    uint256 public override roundTolerance = _INITIAL_ORACLE_TOLERANCE;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the initially supported token / oracle pairs.
     *
     * Applies sanitization in the lengths of the token oracle arrays
     * as well as on a per-pair basis ensuring that they have been
     * strictly set. Finally, transfers ownership of the contract
     * to the BIOP DAO.
     */
    constructor(
        IERC20[] memory supportedTokens,
        IAggregatorV3[] memory tokenOracles,
        address _dao
    ) public {
        require(
            supportedTokens.length == tokenOracles.length,
            "BIOPOracle::constructor: Incorrect Token / Oracle Length"
        );

        chainlinkOracle[IERC20(_ETHER)] = IAggregatorV3(
            _ETH_MAINNET_CHAINLINK_ORACLE
        );

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IERC20 token = supportedTokens[i];
            IAggregatorV3 oracle = tokenOracles[i];

            require(
                token != IERC20(0) && oracle != IAggregatorV3(0),
                "BIOPOracle::constructor: Invalid Token / Oracle Pair"
            );

            chainlinkOracle[token] = oracle;
        }

        transferOwnership(_dao);
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the price of Ether via the Chainlink oracle system.
     */
    function getEtherPrice() external view override returns (uint256) {
        (, uint256 price) = _getPrice(IERC20(_ETHER));
        return price;
    }

    /**
     * @dev Returns the price of the specified token via the Chainlink oracle system.
     */
    function getPrice(IERC20 token)
        external
        view
        override
        returns (uint80, uint256)
    {
        return _getPrice(token);
    }

    /**
     * @dev Returns the price of a token at a particulat round via the Chainlink oracle system.
     *
     * Requirements:
     *
     * - the price and timestamp for the round exists
     */
    function getPrice(IERC20 token, uint80 round)
        external
        view
        override
        returns (uint256)
    {
        (, int256 price, , uint256 timestamp, ) = chainlinkOracle[token]
            .getRoundData(round);

        require(
            price > 0 && timestamp > 0,
            "BIOPOracle::_getPrice: Data Malformed"
        );

        return uint256(price);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows the source of a token to be updated by the DAO.
     *
     * Emits an {OracleChanged} event indicating the previous and new oracles.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function updateSource(IERC20 token, IAggregatorV3 source)
        external
        override
        onlyOwner
    {
        emit OracleChanged(token, chainlinkOracle[token], source);

        chainlinkOracle[token] = source;
    }

    /**
     * @dev Allows the round tolerance of the BIOP oracle system to be updated.
     *
     * Emits a {ToleranceChanged} event indicating the previous and new tolerances.
     *
     * Requirements:
     *
     * - the caller must be the DAO
     */
    function updateTolerance(uint256 _roundTolerance)
        external
        override
        onlyOwner
    {
        require(
            _roundTolerance > roundTolerance,
            "BIOPOracle::updateTolerance: Round Tolerance Only Increases"
        );

        emit ToleranceChanged(roundTolerance, _roundTolerance);

        roundTolerance = _roundTolerance;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Retrieves the price of a token as well as what round it was answered in.
     *
     * Requirements:
     *
     * - the round the price was answered in must not deviate by more than the
     * tolerance from the latest round
     * - the price reported must be non-zero
     */
    function _getPrice(IERC20 token) private view returns (uint80, uint256) {
        (
            uint80 roundID,
            int256 price,
            ,
            ,
            uint80 answeredInRound
        ) = chainlinkOracle[token].latestRoundData();

        require(
            roundID - answeredInRound <= roundTolerance,
            "BIOPOracle::_getPrice: Stale Data"
        );
        require(price > 0, "BIOPOracle::_getPrice: Data Malformed");

        return (roundID, uint256(price));
    }
}
