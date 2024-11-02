// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IGearingToken is IERC721 {
    struct GtConfig {
        address market;
        address collateral;
        IERC20 underlying;
        IERC20 ft;
        address treasurer;
        AggregatorV3Interface underlyingOracle;
        uint64 maturity;
        // The loan to collateral of g-token liquidation threshhold
        uint32 liquidationLtv;
        // The loan to collateral while minting g-token
        uint32 maxLtv;
        // Whether liquidating gt when expired or it's ltv bigger than liquidationLtv
        bool liquidatable;
    }

    function setTreasurer(address treasurer) external;

    function getGtConfig() external view returns (GtConfig memory);

    function liquidatable() external view returns (bool);

    function marketAddr() external view returns (address);

    function mint(
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external returns (uint256 id);

    function loanInfo(
        uint256 id
    )
        external
        view
        returns (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralData
        );

    function merge(uint256[] memory ids) external returns (uint256 newId);

    function repay(uint256 id, uint128 repayAmt, bool byUnderlying) external;

    function removeCollateral(uint256 id, bytes memory collateralData) external;

    function addCollateral(uint256 id, bytes memory collateralData) external;

    /// @notice Return the liquidation info of the loan
    /// @param id The id of the G-token
    /// @return isLiquidable Whether the loan is liquidable
    /// @return maxRepayAmt The maximum amount of the debt to be repaid
    function getLiquidationInfo(
        uint256 id
    ) external view returns (bool isLiquidable, uint128 maxRepayAmt);

    function liquidate(uint256 id, uint128 repayAmt) external;

    function delivery(
        uint256 ratio,
        address to
    ) external returns (bytes memory deliveryData);
}
