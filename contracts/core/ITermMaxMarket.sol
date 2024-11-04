// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import "./storage/TermMaxStorage.sol";

interface ITermMaxMarket {
    error MarketHasBeenInitialized();
    error NumeratorMustLessThanBasicDecimals();
    error MarketIsNotOpen();
    error MarketWasClosed();
    error UnSupportedToken();
    error UnexpectedAmount(
        address sender,
        uint128 expectedAmt,
        uint128 actualAmt
    );
    error DebtTooSmall(address sender, uint128 debt);

    error MintGtFailedCallback(
        address sender,
        uint128 xtAmt,
        uint128 debtAmt,
        bytes callbackData
    );

    error CanNotRedeemBeforeFinalLiquidationDeadline(uint256 deadline);

    error InvalidTime(uint64 openTime, uint64 maturity);
    error CollateralCanNotEqualUnserlyinng();

    event MarketDeployed(
        address indexed deployer,
        address indexed collateral,
        IERC20 indexed underlying,
        uint64 openTime,
        uint64 maturity,
        IMintableERC20[4] tokens,
        IGearingToken gt
    );

    event ProvideLiquidity(
        address indexed sender,
        uint256 underlyingAmt,
        uint128 lpFtAmt,
        uint128 lpXtAmt
    );

    event AddLiquidity(
        address indexed sender,
        uint256 underlyingAmt,
        uint128 ftMintedAmt,
        uint128 xtMintedAmt
    );

    event WithdrawLP(
        address indexed from,
        uint128 lpFtAmt,
        uint128 lpXtAmt,
        uint128 ftOutAmt,
        uint128 xtOutAmt,
        int64 newApr
    );

    event BuyToken(
        address indexed sender,
        IMintableERC20 indexed token,
        uint128 expectedAmt,
        uint128 actualAmt,
        int64 newApr
    );

    event SellToken(
        address indexed sender,
        IMintableERC20 indexed token,
        uint128 expectedAmt,
        uint128 actualAmt,
        int64 newApr
    );

    event MintGt(
        address indexed sender,
        uint256 indexed gtId,
        uint128 debtAmt,
        bytes collateralData
    );

    event Redeem(
        address indexed sender,
        uint128 ratio,
        uint128 underlyingAmt,
        bytes deliveryData
    );

    event RedeemFxAndXtToUnderlying(
        address indexed sender,
        uint256 underlyingAmt
    );

    event UpdateFeeRatio(
        uint32 lendFeeRatio,
        uint32 minNLendFeeR,
        uint32 borrowFeeRatio,
        uint32 minNBorrowFeeR,
        uint32 redeemFeeRatio,
        uint32 leverfeeRatio,
        uint32 lockingPercentage,
        uint32 protocolFeeRatio
    );

    event UpdateTreasurer(address indexed treasurer);

    function initialize(
        IMintableERC20[4] memory tokens_,
        IGearingToken gt_,
        MarketConfig memory config_
    ) external;

    function config() external view returns (MarketConfig memory);

    function setFeeRatio(
        uint32 lendFeeRatio,
        uint32 minNLendFeeR,
        uint32 borrowFeeRatio,
        uint32 minNBorrowFeeR,
        uint32 redeemFeeRatio,
        uint32 leverfeeRatio,
        uint32 lockingPercentage,
        uint32 protocolFeeRatio
    ) external;

    function setTreasurer(address treasurer) external;

    function tokens()
        external
        view
        returns (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingToken gt,
            address collateral,
            IERC20 underlying
        );

    // provide liquidity get lp tokens
    function provideLiquidity(
        uint256 underlyingAmt
    ) external returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt);

    function withdrawLp(
        uint128 lpFtAmt,
        uint128 lpXtAmt
    ) external returns (uint128 ftOutAmt, uint128 xtOutAmt);

    function redeemFtAndXtToUnderlying(uint256 underlyingAmt) external;

    function buyFt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external returns (uint256 netOut);

    function sellXt(
        uint128 xtAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    // use collateral to mint ft and gt
    function lever(
        uint128 debt,
        bytes calldata collateralData
    ) external returns (uint256 gtId);

    function mintGt(
        uint128 debt,
        bytes calldata callbackData
    ) external returns (uint256 gtId);

    function redeem(uint256[4] calldata amountArray) external;

    // function redeemByPermit(
    //     address sender,
    //     uint256[4] calldata amountArray,
    //     uint256[4] calldata deadlineArray,
    //     uint8[4] calldata vArray,
    //     bytes32[4] calldata rArrray,
    //     bytes32[4] calldata sArray
    // ) external;
}
