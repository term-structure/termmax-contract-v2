// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGearingToken, AggregatorV3Interface} from "../tokens/IGearingToken.sol";
import {IMintableERC20} from "../tokens/MintableERC20.sol";
import "../storage/TermMaxStorage.sol";

/**
 * @title The Term Max factory
 * @author Term Structure Labs
 */
interface ITermMaxFactory {
    struct DeployParams {
        bytes32 gtKey;
        /// @notice Admin contract of market
        address admin;
        /// @notice Collateral token
        address collateral;
        /// @notice Underlying token
        IERC20Metadata underlying;
        AggregatorV3Interface underlyingOracle;
        uint32 liquidationLtv;
        uint32 maxLtv;
        bool liquidatable;
        MarketConfig marketConfig;
        bytes gtInitalParams;
    }

    function createMarket(
        ITermMaxFactory.DeployParams calldata deployParams
    ) external returns (address market);
}
