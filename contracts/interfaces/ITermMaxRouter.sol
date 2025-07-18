// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITermMaxRouter as ITermMaxRouterV1} from "../v1/router/ITermMaxRouter.sol";
import {ITermMaxRouterV2} from "../v2/router/ITermMaxRouterV2.sol";

/**
 * @title TermMax Router interface
 * @author Term Structure Labs
 */
interface ITermMaxRouter is ITermMaxRouterV1, ITermMaxRouterV2 {}
