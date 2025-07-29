// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {ITermMaxOrder} from "../../v1/ITermMaxOrder.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {CurveCuts, OrderConfig} from "../../v1/storage/TermMaxStorage.sol";
import {OrderInitialParams} from "../ITermMaxOrderV2.sol";
import {VersionV2} from "../VersionV2.sol";
import {DelegateAble} from "../lib/DelegateAble.sol";

/**
 * @title MakerHelper
 * @notice Helper contract for placing orders and other operations for the maker in the TermMax protocol
 */
contract MakerHelper is UUPSUpgradeable, Ownable2StepUpgradeable, IERC721Receiver, VersionV2 {
    using TransferUtilsV2 for IERC20;

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init_unchained();
        __Ownable_init_unchained(admin);
    }

    /**
     * @notice Places an order and mints a GT token(The gt token will not be linked to the order)
     * @dev This function is used to create a new order in the TermMax protocol
     * @param market The market to place the order in
     * @param maker The address of the maker placing the order
     * @param collateralToMintGt Amount of collateral to mint GT tokens
     * @param debtTokenToDeposit Amount of debt tokens to deposit
     * @param ftToDeposit Amount of FT tokens to deposit
     * @param xtToDeposit Amount of XT tokens to deposit
     * @param orderConfig Configuration parameters for the order
     * @return order The created ITermMaxOrder instance
     * @return gtId The ID of the minted GT token
     */
    function placeOrderForV1(
        ITermMaxMarket market,
        address maker,
        uint256 collateralToMintGt,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        OrderConfig memory orderConfig
    ) external returns (ITermMaxOrder order, uint256 gtId) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 debtToken) = market.tokens();
        if (collateralToMintGt > 0) {
            IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralToMintGt);
            IERC20(collateral).safeIncreaseAllowance(address(gt), collateralToMintGt);
            (gtId,) = market.issueFt(maker, 0, abi.encode(collateralToMintGt));
        }
        order = market.createOrder(maker, orderConfig.maxXtReserve, orderConfig.swapTrigger, orderConfig.curveCuts);

        if (debtTokenToDeposit > 0) {
            debtToken.safeTransferFrom(msg.sender, address(this), debtTokenToDeposit);
            debtToken.safeIncreaseAllowance(address(market), debtTokenToDeposit);
            market.mint(address(order), debtTokenToDeposit);
        }
        ft.safeTransferFrom(msg.sender, address(order), ftToDeposit);
        xt.safeTransferFrom(msg.sender, address(order), xtToDeposit);
    }

    /**
     * @notice Places an order and mints a GT token(the gt token will be linked to the order)
     * @dev This function is used to create a new order in the TermMax protocol
     * @param market The market to place the order in
     * @param collateralToMintGt Amount of collateral to mint GT tokens
     * @param debtTokenToDeposit Amount of debt tokens to deposit
     * @param ftToDeposit Amount of FT tokens to deposit
     * @param xtToDeposit Amount of XT tokens to deposit
     * @param initialParams Configuration parameters for the order
     * @param delegateParams Parameters for delegation
     * @param delegateSignature Signature for delegation
     * @return order The created ITermMaxOrder instance
     * @return gtId The ID of the minted GT token
     */
    function placeOrderForV2(
        ITermMaxMarket market,
        uint256 collateralToMintGt,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        OrderInitialParams memory initialParams,
        DelegateAble.DelegateParameters memory delegateParams,
        DelegateAble.Signature memory delegateSignature
    ) external returns (ITermMaxOrder, uint256) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 debtToken) = market.tokens();
        if (collateralToMintGt > 0) {
            IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralToMintGt);
            IERC20(collateral).safeIncreaseAllowance(address(gt), collateralToMintGt);
            (initialParams.orderConfig.gtId,) = market.issueFt(initialParams.maker, 0, abi.encode(collateralToMintGt));
        }
        ITermMaxOrder order = ITermMaxMarketV2(address(market)).createOrder(initialParams);
        if (delegateParams.delegator != address(0)) {
            DelegateAble(address(gt)).setDelegateWithSignature(delegateParams, delegateSignature);
        }

        if (debtTokenToDeposit > 0) {
            debtToken.safeTransferFrom(msg.sender, address(this), debtTokenToDeposit);
            if (initialParams.pool != IERC4626(address(0))) {
                debtToken.safeIncreaseAllowance(address(initialParams.pool), debtTokenToDeposit);
                // if the order has a pool, we need to deposit the debt token to the pool
                initialParams.pool.deposit(debtTokenToDeposit, address(order));
            } else {
                // if the order does not have a pool, we need to mint the ft/xt token directly
                debtToken.safeIncreaseAllowance(address(market), debtTokenToDeposit);
                market.mint(address(order), debtTokenToDeposit);
            }
        }
        ft.safeTransferFrom(msg.sender, address(order), ftToDeposit);
        xt.safeTransferFrom(msg.sender, address(order), xtToDeposit);
        return (order, initialParams.orderConfig.gtId);
    }

    function onERC721Received(address, address, uint256, bytes memory) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
