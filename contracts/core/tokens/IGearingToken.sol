// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title TermMax Gearing token interface
 * @author Term Structure Labs
 */
interface IGearingToken is IERC721Enumerable {
    /// @notice Data of Gearing Token's configuturation
    struct GtConfig {
        /// @notice The market's address
        address market;
        /// @notice The address of collateral token
        address collateral;
        /// @notice The underlying(debt) token
        IERC20Metadata underlying;
        /// @notice The bond token
        IERC20 ft;
        /// @notice The treasurer's address, which will receive protocol reward while liquidation
        address treasurer;
        /// @notice The price feed of underlying token
        AggregatorV3Interface underlyingOracle;
        /// @notice The unix time of maturity date
        uint64 maturity;
        /// @notice The debt liquidation threshold
        ///         If the loan to collateral is greater than or equal to this value,
        ///         it will be liquidated
        ///         i.e. 0.9e8 means debt value is the 90% of collateral value
        uint32 liquidationLtv;
        /// @notice Maximum loan to collateral when borrowing
        ///         i.e. 0.85e8 means debt value is the 85% of collateral value
        uint32 maxLtv;
        /// @notice The flag to indicate debt is liquidatable or not
        /// @dev    If liquidatable is false, the collateral can only be delivered after maturity
        bool liquidatable;
    }

    /// @notice Error for minting gt when the swtich is close
    error CanNotMintGtNow();
    /// @notice Error for merge loans have different owners
    /// @param id The id of Gearing Token has different owner
    /// @param diffOwner The different owner
    error CanNotMergeLoanWithDiffOwner(uint256 id, address diffOwner);
    /// @notice Error for liquidate loan when Gearing Token don't support liquidation
    error GtDoNotSupportLiquidation();
    /// @notice Error for repay the loan after maturity day
    /// @param id The id of Gearing Token
    error GtIsExpired(uint256 id);
    /// @notice Error for liquidate loan when its ltv less than liquidation threshhold
    /// @param id The id of Gearing Token
    error GtIsSafe(uint256 id);
    /// @notice Error for the ltv of loan is bigger than maxium ltv
    /// @param id The id of Gearing Token
    /// @param owner The owner of Gearing Token
    /// @param ltv The loan to value
    error GtIsNotHealthy(uint256 id, address owner, uint128 ltv);
    /// @notice Error for the ltv increase after liquidation
    /// @param id The id of Gearing Token
    /// @param ltvBefore Loan to value before liquidation
    /// @param ltvAfter Loan to value after liquidation
    error LtvIncreasedAfterLiquidation(
        uint256 id,
        uint128 ltvBefore,
        uint128 ltvAfter
    );
    /// @notice Error for unauthorized operation
    /// @param id The id of Gearing Token
    error CallerIsNotTheOwner(uint256 id);
    /// @notice Error for liquidate the loan with invalid repay amount
    /// @param id The id of Gearing Token
    /// @param repayAmt The id of Gearing Token
    /// @param maxRepayAmt The maxium repay amount when liquidating or repaying
    error RepayAmtExceedsMaxRepayAmt(
        uint256 id,
        uint128 repayAmt,
        uint128 maxRepayAmt
    );
    /// @notice Error for liquidate the loan after liquidation window
    error CanNotLiquidationAfterFinalDeadline(
        uint256 id,
        uint256 liquidationDeadline
    );
    /// @notice Error for debt value less than minimal limit
    /// @param debtValue The debtValue is USD, decimals 1e8
    error DebtValueIsTooSmall(uint256 debtValue);

    /// @notice Emitted when updating the switch of minting gt
    event UpdateMintingSwitch(bool canMintGt);

    /// @notice Emitted when merging multiple Gearing Tokens into one
    /// @param owner The owner of those tokens
    /// @param newId The id of new Gearing Token
    /// @param ids The array of Gearing Tokens id were merged
    event MergeGts(address indexed owner, uint256 indexed newId, uint256[] ids);

    /// @notice Emitted when removing collateral from the loan
    /// @param id The id of Gearing Token
    /// @param newCollateralData Collateral data after removal
    event RemoveCollateral(uint256 indexed id, bytes newCollateralData);

    /// @notice Emitted when adding collateral to the loan
    /// @param id The id of Gearing Token
    /// @param newCollateralData Collateral data after additional
    event AddCollateral(uint256 indexed id, bytes newCollateralData);

    /// @notice Emitted when repaying the debt of Gearing Token
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt repaid
    /// @param byUnderlying Repay using underlying token or bonds token
    event Repay(uint256 indexed id, uint256 repayAmt, bool byUnderlying);

    /// @notice Emitted when liquidating Gearing Token
    /// @param id The id of Gearing Token
    /// @param liquidator The liquidator
    /// @param repayAmt The amount of debt liquidated
    /// @param cToLiquidator Collateral data assigned to liquidator
    /// @param cToTreasurer Collateral data assigned to protocol
    /// @param remainningC Remainning collateral data
    event Liquidate(
        uint256 indexed id,
        address indexed liquidator,
        uint128 repayAmt,
        bytes cToLiquidator,
        bytes cToTreasurer,
        bytes remainningC
    );

    // @notice Initial function
    /// @param name The token's name
    /// @param symbol The token's symbol
    /// @param config Configuration of GT
    /// @param initalParams The initilization parameters of implementation
    function initialize(
        string memory name,
        string memory symbol,
        GtConfig memory config,
        bytes memory initalParams
    ) external;

    /// @notice Set the treasurer address
    /// @param treasurer New address of treasurer
    /// @dev Only the market can call this function
    function setTreasurer(address treasurer) external;

    /// @notice Update the switch of minting gt
    function updateMintingSwitch(bool canMintGt) external;

    /// @notice Return the configuration of Gearing Token
    function getGtConfig() external view returns (GtConfig memory);

    /// @notice Return the flag to indicate debt is liquidatable or not
    function liquidatable() external view returns (bool);

    /// @notice Return the market's address
    function marketAddr() external view returns (address);

    /// @notice Mint this token to an address
    /// @param  collateralProvider Who provide collateral token
    /// @param  to The address receiving token
    /// @param  debtAmt The amount of debt, unit by underlying token
    /// @param  collateralData The encoded data of collateral
    /// @return id The id of Gearing Token
    /// @dev Only the market can mint Gearing Token
    function mint(
        address collateralProvider,
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external returns (uint256 id);

    /// @notice Return the loan information of Gearing Token
    /// @param  id The id of Gearing Token
    /// @return owner The owner of Gearing Token
    /// @return debtAmt The amount of debt, unit by underlying token
    /// @return ltv The loan to collateral
    /// @return collateralData The encoded data of collateral
    function loanInfo(
        uint256 id
    )
        external
        view
        returns (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralData
        );

    /// @notice Merge multiple Gearing Tokens into one
    /// @param  ids The array of Gearing Tokens to be merged
    /// @return newId The id of new Gearing Token
    function merge(uint256[] memory ids) external returns (uint256 newId);

    /// @notice Repay the debt of Gearing Token.
    ///         If repay amount equals the debt amount, Gearing Token's owner will get his collateral.
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt you want to repay
    /// @param byUnderlying Repay using underlying token or bonds token
    function repay(uint256 id, uint128 repayAmt, bool byUnderlying) external;

    /// @notice Repay the debt of Gearing Token,
    ///         the collateral will send by flashloan first.
    /// @param id The id of Gearing Token
    function flashRepay(uint256 id, bytes calldata callbackData) external;

    /// @notice Remove collateral from the loan.
    ///         Require the loan to value bigger than maxLtv after this action.
    /// @param id The id of Gearing Token
    /// @param collateralData Collateral data to be removed
    function removeCollateral(uint256 id, bytes memory collateralData) external;

    /// @notice Add collateral to the loan
    /// @param id The id of Gearing Token
    /// @param collateralData Collateral data to be added
    function addCollateral(uint256 id, bytes memory collateralData) external;

    /// @notice Return the liquidation info of the loan
    /// @param  id The id of the G-token
    /// @return isLiquidable Whether the loan is liquidable
    /// @return maxRepayAmt The maximum amount of the debt to be repaid
    function getLiquidationInfo(
        uint256 id
    ) external view returns (bool isLiquidable, uint128 maxRepayAmt);

    /// @notice Liquidate the loan when its ltv bigger than liquidationLtv or expired.
    ///         The ltv can not inscrease after liquidation.
    ///         A maximum of 10% of the repayment amount of collateral is given as a
    ///         reward to the protocol and liquidator,
    ///         The proportion of collateral liquidated will not exceed the debt liquidation ratio.
    /// @param  id The id of the G-token
    /// @param  repayAmt The amount of the debt to be liquidate
    function liquidate(uint256 id, uint128 repayAmt) external;

    /// @notice Deilivery outstanding debts after maturity
    /// @param  proportion The proportion of collateral that should be obtained
    /// @param  to The address receiving collateral token
    /// @dev    Only the market can delivery collateral
    function delivery(
        uint256 proportion,
        address to
    ) external returns (bytes memory deliveryData);

    /// @notice Return the value of collateral in USD with base decimals
    /// @param collateralData encoded collateral data
    /// @return collateralValue collateral's value in USD
    function getCollateralValue(
        bytes memory collateralData
    ) external view returns (uint256 collateralValue);

    /// @notice Suspension of Gearing Token liquidation and collateral reduction
    function pause() external;

    /// @notice Open Gearing Token liquidation and collateral reduction
    function unpause() external;
}
