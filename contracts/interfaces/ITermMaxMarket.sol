// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITermMaxMarket as ITermMaxMarketV1} from "../v1/ITermMaxMarket.sol";
import {ITermMaxMarketV2} from "../v2/ITermMaxMarketV2.sol";

/**
 * @title TermMax Market interface
 * @author Term Structure Labs
 */
interface ITermMaxMarket is ITermMaxMarketV1, ITermMaxMarketV2 {}
