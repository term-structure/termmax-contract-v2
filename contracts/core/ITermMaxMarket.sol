// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingNft} from "./tokens/IGearingNft.sol";
import {TermMaxStorage} from "../core/storage/TermMaxStorage.sol";

interface ITermMaxMarket {
    error MarketMustHasLiquidationStrategy();
    error MarketHasBeenInitialized();
    error NumeratorMustLessThanBasicDecimals();
    error MarketIsNotOpen();
    error MarketWasClosed();
    error UnSupportedToken();
    error UnexpectedAmount(
        address sender,
        IMintableERC20 token,
        uint128 expectedAmt,
        uint128 actualAmt
    );
    error DebtTooSmall(address sender, uint128 debt);

    error MintGNFTFailedCallback(
        address sender,
        uint128 xtAmt,
        uint128 debtAmt,
        bytes callbackData
    );
    error MarketDoNotSupportLiquidation();
    error CanNotLiquidateAfterMaturity();
    error CanNotRedeemBeforeMaturity();

    error InvalidTime(uint64 openTime, uint64 maturity);
    error CollateralCanNotEqualUnserlyinng();

    event MarketDeployed(
        address indexed deployer,
        address indexed collateral,
        IERC20 indexed underlying,
        uint64 openTime,
        uint64 maturity,
        IMintableERC20[4] tokens,
        IGearingNft gnft
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

    event MintGNft(
        address indexed sender,
        uint256 indexed nftId,
        uint128 debtAmt,
        bytes collateralData
    );

    event RepayGNft(
        address indexed sender,
        uint256 indexed nftId,
        uint128 repayAmt,
        bool isPaidOff
    );

    event DeregisterGNft(
        address indexed sender,
        uint256 indexed nftId,
        uint128 debtAmt
    );

    event LiquidateGNft(
        address indexed liquidator,
        uint256 indexed nftId,
        uint128 liquidatedAmt
    );

    event Redeem(
        address indexed sender,
        uint128 ratio,
        uint128 underlyingAmt,
        bytes deliveryData
    );

    event RedeemFxAndXtToUnderlying(address sender, uint256 underlyingAmt);

    function config()
        external
        view
        returns (TermMaxStorage.MarketConfig memory);

    function initialize(
        IMintableERC20[4] memory tokens_,
        IGearingNft gNft_,
        TermMaxStorage.MarketConfig memory config_
    ) external;

    function tokens()
        external
        view
        returns (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingNft gNft,
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

    function redeemFxAndXtToUnderlying(uint256 underlyingAmt) external;

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

    // use collateral to mint ft and nft
    function lever(
        uint128 debt,
        bytes calldata collateralData
    ) external returns (uint256 nftId);

    function mintGNft(
        uint128 debt,
        bytes calldata callbackData
    ) external returns (uint256 nftId);

    function repayGNftByUnderlying(uint256 nftId, uint128 repayAmt) external;

    function repayGNftByFt(uint256 nftId, uint128 repayAmt) external;

    function liquidateGNft(uint256 nftId, uint128 repayAmt) external;

    function redeem() external;
}
