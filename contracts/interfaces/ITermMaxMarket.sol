// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "../interfaces/IMintableERC20.sol";

interface ITermMaxMarket {
    error MarketIsNotOpen();
    error MarketWasClosed();
    error UnSupportedToken();
    error UnexpectedAmount(
        address sender,
        IMintableERC20 token,
        uint128 expectedAmt,
        uint128 actualAmt
    );
    error XTAmountTooLittle(
        address sender,
        uint128 xtAmt,
        bytes collateralData
    );
    error FTAmountTooLittle(
        address sender,
        uint128 ftAmt,
        bytes collateralData
    );
    error GNftIsNotHealthy(
        address sender,
        uint128 debtAmt,
        uint128 health,
        bytes collateralData
    );
    error GNftIsHealthy(address sender, uint256 nftId, uint128 health);
    error MintGNFTFailedCallback(
        address sender,
        uint128 xtAmt,
        uint128 debtAmt,
        bytes callbackData
    );
    error MarketDoNotSupportLiquidation();
    error CanNotLiquidateAfterMaturity();
    error SenderIsNotTheGNftOwner(address sender, uint256 nftId);
    error CanNotRedeemBeforeMaturity();
    error CanNotMergeLoanWithDiffOwner();

    event ProvideLiquidity(
        address indexed sender,
        uint256 cashAmt,
        uint128 lpFtAmt,
        uint128 lpXtAmt
    );

    event AddLiquidity(
        address indexed sender,
        uint256 cashAmt,
        uint128 ftMintedAmt,
        uint128 xtMintedAmt
    );

    event WithdrawLP(
        address indexed from,
        uint128 lpFtAmt,
        uint128 lpXtAmt,
        uint128 ftOutAmt,
        uint128 xtOutAmt,
        int64 newApy
    );

    event BuyToken(
        address indexed sender,
        IMintableERC20 indexed token,
        uint128 expectedAmt,
        uint128 actualAmt,
        int64 newApy
    );

    event SellToken(
        address indexed sender,
        IMintableERC20 indexed token,
        uint128 expectedAmt,
        uint128 actualAmt,
        int64 newApy
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
        address indexed sender,
        uint256 indexed nftId,
        uint128 debtAmt
    );

    event MergeGNfts(
        address indexed sender,
        uint256 indexed newNftId,
        uint256[] nftIds
    );

    event Redeem(
        address indexed sender,
        uint128 ratio,
        uint128 cashAmt,
        bytes deliveryData
    );

    // provide liquidity get lp tokens
    function provideLiquidity(
        uint256 cashAmt
    ) external returns (uint128 lpXtOutAmt, uint128 lpFtOutAmt);

    function withdrawLp(
        uint128 lpFtAmt,
        uint128 lpXtAmt
    ) external returns (uint128 ftOutAmt, uint128 xtOutAmt);

    function buyFt(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    function buyXt(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    // use collateral to mint ft and nft
    function lever(
        uint128 debtAmt,
        bytes calldata collateralData
    ) external returns (uint256 nftId);

    function mintGNft(
        uint128 xtAmt,
        bytes calldata collateralData,
        bytes calldata callbackData
    ) external returns (uint256 nftId);

    function getGNftInfo(
        uint256 nftId
    )
        external
        view
        returns (address owner, uint128 debtAmt, bytes memory collateralData);

    // use cash to repayDebt
    function repayGNft(uint256 nftId, uint128 repayAmt) external;

    function liquidateGNft(uint256 nftId) external;

    // use ft to deregister debt
    function deregisterGNft(uint256 nftId) external;

    function mergeLoan(
        uint256[] memory nftIds
    ) external returns (uint256 nftId);

    function redeem() external;
}
