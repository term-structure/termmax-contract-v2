// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGearingToken, AggregatorV3Interface} from "../tokens/ERC20GearingToken.sol";
import {IMintableERC20} from "../tokens/MintableERC20.sol";
import "../storage/TermMaxStorage.sol";

interface ITermMaxFactory {
    struct DeployParams {
        address admin;
        IERC20Metadata collateral;
        IERC20Metadata underlying;
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
