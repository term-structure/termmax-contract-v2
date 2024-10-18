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
        uint128 yaAmt,
        bytes collateralData
    );
    error GNftIsNotHealthy(
        address sender,
        uint128 yaAmt,
        uint128 health,
        bytes collateralData
    );
    error MintGNFTFailedCallback(
        address sender,
        uint128 yaAmt,
        uint128 debtAmt,
        bytes callbackData
    );

    event ProvideLiquidity(
        address indexed sender,
        uint256 cashAmt,
        uint128 lpYpAmt,
        uint128 lpYaAmt
    );

    event AddLiquidity(
        address indexed sender,
        uint256 cashAmt,
        uint128 ypMintedAmt,
        uint128 yaMintedAmt
    );

    event WithdrawLP(
        address indexed from,
        uint128 lpYpAmt,
        uint128 lpYaAmt,
        uint128 ypOutAmt,
        uint128 yaOutAmt,
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
        uint128 xtAmt,
        uint128 debtAmt,
        bytes collateralData
    );

    // provide liquidity get lp tokens
    function provideLiquidity(
        uint256 cashAmt
    ) external returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt);

    function withdrawLp(
        uint128 lpYpAmt,
        uint128 lpYaAmt
    ) external returns (uint128 ypOutAmt, uint128 yaOutAmt);

    function buyYp(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    function buyYa(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    // use collateral to mint yp and nft
    function lever(
        uint128 debtAmt,
        bytes calldata collateralData
    ) external returns (uint256 nftId);

    function mintGNft(
        uint128 yaAmt,
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
    function repayGNft(uint256 nftId, uint256 repayAmt) external;

    // can use yp token?
    function liquidateGNft(uint256 nftId) external;

    // use yp to deregister debt
    function deregisterGNft(uint256 nftId) external;

    function redeem() external returns (uint256);
}
