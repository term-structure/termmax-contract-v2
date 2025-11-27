// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
// import {VersionV2} from "../../VersionV2.sol";

// contract TermMaxStrBTCPriceFeedAdapter is VersionV2 {
//     AggregatorV3Interface public immutable strBTCPriceFeed;
//     AggregatorV3Interface public immutable btcPriceFeed;

//     uint256 immutable priceDenominator;
//     address public immutable asset;
//     uint256 constant PRICE_DENOMINATOR = 10 ** 8;

//     constructor(address _aTokenToBTokenPriceFeed, address _bTokenToCTokenPriceFeed, address _asset) {
//         asset = _asset;
//         aTokenToBTokenPriceFeed = AggregatorV3Interface(_aTokenToBTokenPriceFeed);
//         bTokenToCTokenPriceFeed = AggregatorV3Interface(_bTokenToCTokenPriceFeed);
//         priceDenominator = 10 ** (aTokenToBTokenPriceFeed.decimals() + bTokenToCTokenPriceFeed.decimals());
//     }

//     function decimals() public view returns (uint8) {
//         return 8;
//     }

//     function description() external view returns (string memory) {
//         string memory symbol = IERC20Metadata(asset).symbol();
//         return string(abi.encodePacked("TermMax price feed: ", symbol, "/USD"));
//     }
// }
