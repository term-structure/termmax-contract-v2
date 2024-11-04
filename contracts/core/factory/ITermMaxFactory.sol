// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGearingToken, AggregatorV3Interface} from "../tokens/GearingTokenWithERC20.sol";
import {IMintableERC20} from "../tokens/MintableERC20.sol";
import "../storage/TermMaxStorage.sol";

/**
 * @title The Term Max factory
 * @author Term Structure Labs
 */
interface ITermMaxFactory {
    struct DeployParams {
        /// @notice Admin contract of market
        address admin;
        /// @notice Collateral token
        IERC20Metadata collateral;
        /// @notice Underlying token
        IERC20Metadata underlying;
        /// @notice Underlying token
        AggregatorV3Interface collateralOracle;
        AggregatorV3Interface underlyingOracle;
        uint32 liquidationLtv;
        uint32 maxLtv;
        bool liquidatable;
        MarketConfig marketConfig;
    }

    function createERC20Market(
        ITermMaxFactory.DeployParams calldata deployParams
    ) external returns (address market);
}
