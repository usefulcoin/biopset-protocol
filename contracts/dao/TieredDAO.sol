// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../shared/ProtocolConstants.sol";

import "../interfaces/dao/ITieredDAO.sol";
import "../interfaces/staking/IDAOStaking.sol";
import "../interfaces/token/voting/IvBIOP.sol";
import "../interfaces/options/factory/IOptionFactory.sol";
import "../interfaces/options/rate-calculator/IRateCalculator.sol";
import "../interfaces/options/utilization/IUtilizationRewards.sol";
import "../interfaces/treasury/ITreasury.sol";
import "../interfaces/oracle/IBIOPOracle.sol";
import "../interfaces/token/dex-rewards/IDEXRewards.sol";

/**
 * @dev Implementation of the {ITieredDAO} interface.
 *
 * This implementation contains a unique DAO structure whereby users
 * with sufficient delegates can immediately invoke functions the DAO
 * exposes based on their access tiers. The idea behind this implementation
 * is that the tier thresholds are increased in contrast to conventional DAO
 * systems, making it hard to acquire a delegation of such magnitude.
 *
 * The DAO controls many configurational parameters of the protocol and as such
 * is one of the highest-value assets of the system whose security should not
 * be compromised.
 */
contract TieredDAO is ITieredDAO, ProtocolConstants {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // The DAO staking contract, used for configuration
    IDAOStaking public immutable staking;

    // The voting BIOP contract, used for power calculations
    IvBIOP public immutable vBIOP;

    // The option factory contract, used for creating new option contracts
    IOptionFactory public immutable factory;

    // The treasury contract, used for configuration and management
    ITreasury public immutable treasury;

    // The BIOP oracle contract, used for configuration
    IBIOPOracle public immutable oracle;

    // The utilization rewards contract, used for configuration
    IUtilizationRewards public immutable utilization;

    // The DEX rewards contract, used for configuration
    IDEXRewards public immutable dexRewards;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the values for all BIOP system components.
     *
     * Each component is validated to have been strictly set to prevent misconfiguration of the system.
     */
    constructor(
        IDAOStaking _staking,
        IvBIOP _vBIOP,
        IOptionFactory _factory,
        ITreasury _treasury,
        IBIOPOracle _oracle,
        IUtilizationRewards _utilization,
        IDEXRewards _dexRewards
    ) public {
        require(
            _staking != IDAOStaking(0) &&
                _vBIOP != IvBIOP(0) &&
                _factory != IOptionFactory(0) &&
                _treasury != ITreasury(0) &&
                _oracle != IBIOPOracle(0) &&
                _utilization != IUtilizationRewards(0) &&
                _dexRewards != IDEXRewards(0),
            "TieredDAO::constructor: Misconfiguration"
        );

        staking = _staking;
        vBIOP = _vBIOP;
        factory = _factory;
        treasury = _treasury;
        oracle = _oracle;
        utilization = _utilization;
        dexRewards = _dexRewards;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Calculates the access tier of a particular user
     */
    function getTier(address user) public view returns (Tier) {
        uint256 total = vBIOP.totalSupply();
        uint256 power = vBIOP.balanceOf(user);

        if (_portion(power, total, _TIER_FOUR_PORTION)) return Tier.FOUR;
        else if (_portion(power, total, _TIER_THREE_PORTION)) return Tier.THREE;
        else if (_portion(power, total, _TIER_TWO_PORTION)) return Tier.TWO;
        else if (_portion(power, total, _TIER_ONE_PORTION)) return Tier.ONE;
        else return Tier.ZERO;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows an option to be created for a particular token.
     */
    function createOption(ERC20 token) external {
        IOption option = factory.createOption(token);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /*



                                                              .-=
                      =                               :-=+#%@@@@@
               @+@+* -*   -==: ==-+.           -=+#%@@@@@@@@@@@@@
                :%    %. -%-=* :%              %@@@@@@@@@@@@@@@@@
               .=== .===: -==: ===.            %@@@@%*+=--@@@@@@@
                                               --.       .@@@@@@@
                                                         .@@@@@@@
                                                         .@@@@@@@
                                                         .@@@@@@@
                                                         .@@@@@@@
                                                         .@@@@@@@
                                                         .@@@@@@@
                      .:    :.                           .@@@@@@@
                     -@@#  #@@=                          .@@@@@@@
                     +@@#  %@@=                          .@@@@@@@
                     *@@*  @@@-                          .@@@@@@@
                     #@@+ .@@@:                          .@@@@@@@
                 .---@@@*-+@@@=--                        .@@@@@@@
                 +@@@@@@@@@@@@@@@.                       .@@@@@@@
                    .@@@: =@@@                           .@@@@@@@
                    :@@@. +@@#                           .@@@@@@@
                 -*##@@@##%@@@##*                        .@@@@@@@
                 -##%@@@##@@@%##*                        .@@@@@@@
                    +@@#  #@@=                           .@@@@@@@
                    *@@*  @@@:                           .@@@@@@@
                    *@@+  @@@.                 +**********@@@@@@@**********=
                    #@@= .@@@                  %@@@@@@@@@@@@@@@@@@@@@@@@@@@%
                    .--   :=:                  %@@@@@@@@@@@@@@@@@@@@@@@@@@@%






     */

    /**
     * @dev Allows the maximum option rounds of a particular option to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier one voting power / delegation
     * - the option must exist
     */
    function updateMaximumOptionRounds(IERC20 token, uint256 maxRounds)
        external
        onlyTier(Tier.ONE)
    {
        IOption option = _getOption(
            token,
            "TieredDAO::updateMaximumOptionRounds: Inexistent Option"
        );

        option.updateMaximumRounds(maxRounds);
    }

    /**
     * @dev Allows the minimum option rounds of a particular option to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier one voting power / delegation
     * - the option must exist
     */
    function updateMinimumOptionRounds(IERC20 token, uint256 minRounds)
        external
        onlyTier(Tier.ONE)
    {
        IOption option = _getOption(
            token,
            "TieredDAO::updateMinimumOptionRounds: Inexistent Option"
        );

        option.updateMinimumRounds(minRounds);
    }

    /**
     * @dev Allows a reward distributor to be adjusted for the DAO staking contract.
     *
     * Requirements:
     *
     * - the caller must have tier one voting power / delegation
     * - the option must exist
     */
    function setRewardDistributor(address distributor, bool status)
        external
        onlyTier(Tier.ONE)
    {
        staking.setDistributorStatus(distributor, status);
    }

    /*


                                                    .:-+*##%@@@@@@%#*+=:
              :::::   *                        .=+#@@@@@@@@@@@@@@@@@@@@@@%+:
              @-@=#: =*.  .+=+- :*=+*:        -@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%=
               .@:    %:  #*--#. **           -@@@@@@@%#+=-::::::-=*@@@@@@@@@@%-
              :+**- :+*++ .++++ -**+          -@@@#=:                :*@@@@@@@@@=
                                              .=.                      :%@@@@@@@@=
                                                                        .@@@@@@@@@.
                                                                         +@@@@@@@@=
                                                                         :@@@@@@@@+
                                                                         -@@@@@@@@=
                                                                         #@@@@@@@@:
                                                                        -@@@@@@@@#
                                                                       :@@@@@@@@%
                                                                      -@@@@@@@@%.
                      *#*   -##-                                    .*@@@@@@@@*
                     =@@@-  @@@%                                   =@@@@@@@@#:
                     +@@@: .@@@#                                 =%@@@@@@@%-
                     *@@@. :@@@*                              .+@@@@@@@@#-
                     #@@@  -@@@=                            .*@@@@@@@@*.
                  ...%@@@..=@@@=..                        :#@@@@@@@%=.
                :@@@@@@@@@@@@@@@@@@                     -%@@@@@@@%-
                 +++*@@@%++%@@@*++=                   :#@@@@@@@#:
                    :@@@+  #@@@                     :#@@@@@@@#:
                    -@@@=  %@@@                    +@@@@@@@%-
                .#%%@@@@@%%@@@@%%%*              -@@@@@@@@*
                .#%%@@@@%%%@@@@%%%*             *@@@@@@@@=
                    #@@@  .@@@*               .%@@@@@@@@-
                    %@@@  :@@@+              .%@@@@@@@@*
                    @@@%  -@@@=              @@@@@@@@@@#**************************.
                    @@@#  =@@@-              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@:
                    @@@+  =@@@.              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@:
                     :.    .:.               @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@:





     */

    /**
     * @dev Allows the settler fee of a particular option to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier two voting power / delegation
     * - the option must exist
     */
    function updateSettlerFee(IERC20 token, uint256 fee)
        external
        onlyTier(Tier.TWO)
    {
        IOption option = _getOption(
            token,
            "TieredDAO::updateSettlerFee: Inexistent Option"
        );

        option.updateSettlerFee(fee);
    }

    /**
     * @dev Allows the gas reward status of an option to be adjusted.
     *
     * Requirements:
     *
     * - the caller must have tier two voting power / delegation
     * - the option must exist
     */
    function setGasRewardStatus(bool status) external onlyTier(Tier.TWO) {
        IOption option = factory.option(IERC20(_ETHER));

        option.setGasRewardStatus(status);
    }

    /**
     * @dev Allows outward transfers of native (ETH) funds from the treasury
     *
     * Requirements:
     *
     * - the caller must have tier two voting power / delegation
     */
    function transferTreasuryNative(address payable destination, uint256 amount)
        external
    {
        transferTreasury(IERC20(_ETHER), destination, amount);
    }

    /**
     * @dev Allows outward transfers of token funds from the treasury
     *
     * Requirements:
     *
     * - the caller must have tier two voting power / delegation
     */
    function transferTreasury(
        IERC20 token,
        address payable destination,
        uint256 amount
    ) public onlyTier(Tier.TWO) {
        treasury.send(token, destination, amount);
    }

    /*


                                                        .:::::::::.
                                               .-=*#%@@@@@@@@@@@@@@@@@#*=:
          -+++++   #.                         %@@@@@@@@@@@@@@@@@@@@@@@@@@@@#=
          +:+%.%  +%-  .*++*: =%++#:          %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+
            +%     %-  +@==+=  @-             %@@@@#*=-:..      .:-+%@@@@@@@@@@%.
           ++++. -++++  -+++. ++++            *+-.                   .+@@@@@@@@@%
                                                                       :@@@@@@@@@-
                                                                        +@@@@@@@@*
                                                                        :@@@@@@@@*
                                                                        :@@@@@@@@+
                                                                        =@@@@@@@@:
                                                                       .@@@@@@@@=
                                                                      :%@@@@@@@=
                                                                    .*@@@@@@@%:
                                                                .:+#@@@@@@@#-
                    .      .                       :======++*#%@@@@@@@@@*-
                  -@@@-  =@@@:                     +@@@@@@@@@@@@@@@@%=.
                  *@@@=  *@@@-                     +@@@@@@@@@@@@@@@@@@@#+-.
                  #@@@-  #@@@:                     -++++++**#%%@@@@@@@@@@@@%+:
                  %@@@.  %@@@.                                  .:=#@@@@@@@@@@%-
                  @@@@   @@@@                                        :*@@@@@@@@@%.
              :::-@@@@:::@@@@:::                                       .#@@@@@@@@@:
             #@@@@@@@@@@@@@@@@@@#                                        #@@@@@@@@@.
             :+++*@@@%++*@@@%+++:                                         @@@@@@@@@+
                 -@@@*  =@@@+                                             *@@@@@@@@#
                 =@@@+  +@@@=                                             +@@@@@@@@%
             =###%@@@%##%@@@%###=                                         *@@@@@@@@#
             *@@@@@@@@@@@@@@@@@@*                                        .@@@@@@@@@+
                 #@@@:  %@@@.                                            %@@@@@@@@@.
                 %@@@.  @@@@                                           .%@@@@@@@@@+
                 @@@@  .@@@%                 +=:                     :*@@@@@@@@@@+
                 @@@@  :@@@#                 %@@@@#+=-.          .-+%@@@@@@@@@@@-
                .@@@%  -@@@*                 %@@@@@@@@@@@@%%%%%@@@@@@@@@@@@@@@=
                 +%#-   *%#:                 %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-
                                             -+*#%@@@@@@@@@@@@@@@@@@@@%*=.
                                                    ..:--=======--:.


     */

    /**
     * @dev Allows the staking reward duration of the DAO staking contract to be adjusted.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     */
    function setStakingRewardDuration(uint256 rewardsDuration)
        external
        onlyTier(Tier.THREE)
    {
        staking.setRewardsDuration(rewardsDuration);
    }

    /**
     * @dev Allows the utilization ETH/BIOP rate to be updated
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     */
    function setUtilizationEthBiopRate(uint256 _rate)
        external
        onlyTier(Tier.THREE)
    {
        utilization.setEthBiopRate(_rate);
    }

    /**
     * @dev Allows the utilization reward period reset to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     */
    function setUtilizationPeriod(uint256 _periodMaximum)
        external
        onlyTier(Tier.THREE)
    {
        utilization.setPeriodMaximum(_periodMaximum);
    }

    /**
     * @dev Allows the lock time of a particular option to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     * - the option must exist
     */
    function updateLockTime(IERC20 token, uint256 lockTime)
        external
        onlyTier(Tier.THREE)
    {
        IOption option = _getOption(
            token,
            "TieredDAO::updateLockTime: Inexistent Option"
        );

        option.updateLockTime(lockTime);
    }

    /**
     * @dev Allows the protocol fee of a particular option to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     * - the option must exist
     */
    function updateProtocolFee(IERC20 token, uint256 fee)
        external
        onlyTier(Tier.THREE)
    {
        IOption option = _getOption(
            token,
            "TieredDAO::updateProtocolFee: Inexistent Option"
        );

        option.updateProtocolFee(fee);
    }

    /**
     * @dev Allows the round tolerance of the BIOP oracle system to be adjusted.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     */
    function updateRoundTolerance(uint256 roundTolerance)
        external
        onlyTier(Tier.THREE)
    {
        oracle.updateTolerance(roundTolerance);
    }

    /**
     * @dev Allows a particular option to be deactivated.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     * - the option must exist
     */
    function deactivateOption(IERC20 token) external onlyTier(Tier.THREE) {
        IOption option = _getOption(
            token,
            "TieredDAO::deactivateOption: Inexistent Option"
        );

        option.deactivateOption();
    }

    /**
     * @dev Allows a new DEX LP token to be added to the reward contract.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     */
    function addDexReward(uint256 _allocPoint, IERC20 _lpToken)
        external
        onlyTier(Tier.THREE)
    {
        dexRewards.add(_allocPoint, _lpToken, true);
    }

    /**
     * @dev Allows an existing DEX LP token's allocation to be adjusted.
     *
     * Requirements:
     *
     * - the caller must have tier three voting power / delegation
     */
    function adjustDexReward(uint256 _pid, uint256 _allocPoint)
        external
        onlyTier(Tier.THREE)
    {
        dexRewards.set(_pid, _allocPoint, true);
    }

    /*





                       -                                       +######:
                %*@*+ =*   -=-  =:==                         .%@@@@@@@-
                .:%    @  +#-+= ++ .                        =@@@@@@@@@-
                .=== .===. -==:.==-                       .#@@@@@@@@@@-
                                                         =@@@@@@%@@@@@-
                                                        *@@@@@#.*@@@@@-
                                                      -@@@@@@+  *@@@@@-
                                                     *@@@@@#.   *@@@@@-
                                                   -@@@@@@=     *@@@@@-
                                                  *@@@@@%.      *@@@@@-
                                                :%@@@@@+        *@@@@@-
                       --   .-:                +@@@@@%:         *@@@@@-
                      +@@*  @@@.             .%@@@@@+           *@@@@@-
                      *@@+  @@@.            =@@@@@%:            *@@@@@-
                      #@@= .@@@           .#@@@@@+              *@@@@@-
                      %@@- -@@%          =@@@@@%-               *@@@@@-
                  :***@@@#*#@@@**=      *@@@@@@#################@@@@@@%######-
                  =#%%@@@%%@@@@%%+      %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+
                     .@@@  +@@+         %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+
                     -@@@  #@@=         .......................:@@@@@@+......
                  +@@@@@@@@@@@@@@#                             .@@@@@@-
                  .-=#@@%==@@@+==:                             .@@@@@@-
                     *@@*  @@@.                                .@@@@@@-
                     #@@+ .@@@                                 .@@@@@@-
                     %@@= :@@@                                 .@@@@@@-
                     *@%. .%@+                                 .@@@@@@-
                                                                ******:

     */

    /**
     * @dev Allows the oracle of a token to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier four voting power / delegation
     */
    function updateOracle(IERC20 token, IAggregatorV3 source)
        external
        onlyTier(Tier.FOUR)
    {
        oracle.updateSource(token, source);
    }

    /**
     * @dev Allows the rate calculator of a particular option to be updated.
     *
     * Requirements:
     *
     * - the caller must have tier four voting power / delegation
     * - the option must exist
     */
    function updateRater(IERC20 token, IRateCalculator calculator)
        external
        onlyTier(Tier.FOUR)
    {
        IOption option = _getOption(
            token,
            "TieredDAO::updateRater: Inexistent Option"
        );

        option.updateRater(calculator);
    }

    /**
     * @dev Allows the treasury tax of each native transfer to be adjusted.
     *
     * Requirements:
     *
     * - the caller must have tier four voting power / delegation
     */
    function updateTreasuryTax(uint256 tax) external onlyTier(Tier.FOUR) {
        treasury.updateTax(tax);
    }

    /**
     * @dev Allows a particular option to be frozen.
     *
     * Requirements:
     *
     * - the caller must have tier four voting power / delegation
     * - the option must exist
     */
    function freezeOption(IERC20 token) external onlyTier(Tier.FOUR) {
        IOption option = _getOption(
            token,
            "TieredDAO::freezeOption: Inexistent Option"
        );

        option.freezeOption();
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Retrieves the option and validates its existance from the option factory.
     */
    function _getOption(IERC20 token, string memory error)
        private
        view
        returns (IOption)
    {
        IOption option = factory.option(token);

        require(option != IOption(0), error);

        return option;
    }

    /**
     * @dev Returns whether the power argument satisfies the target percentage in basis points of the total.
     */
    function _portion(
        uint256 power,
        uint256 total,
        uint256 target
    ) private pure returns (bool) {
        return power >= total.mul(target).div(_MAX_BASIS_POINTS);
    }

    /**
     * @dev Ensures a user with the specified tier (or above) of voting power can access the function.
     */
    function _onlyTier(Tier tier) private view {
        require(
            getTier(msg.sender) >= tier,
            "TieredDAO::_onlyTier: Insufficient Priviledges"
        );
    }

    /**
     * @dev Throws if invoked without the necessary voting power.
     */
    modifier onlyTier(Tier tier) {
        _onlyTier(tier);
        _;
    }
}
