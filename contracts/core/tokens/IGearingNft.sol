// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IGearingNft is IERC721 {
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

    function calculateLtv(
        uint256 debtAmt,
        bytes memory collateralData
    ) external view returns (uint128 ltv, uint256 collateralValue);

    function merge(uint256[] memory ids) external returns (uint256 newId);

    function repay(address sender, uint256 id, uint128 repayAmt) external;

    function removeCollateral(uint256 id, bytes memory collateralData) external;

    function addCollateral(uint256 id, bytes memory collateralData) external;

    /// @notice Return the liquidation info of the loan
    /// @param id The id of the G-Nft
    /// @return isLiquidable Whether the loan is liquidable
    /// @return maxRepayAmt The maximum amount of the debt to be repaid
    function getLiquidationInfo(
        uint256 id
    ) external view returns (bool isLiquidable, uint128 maxRepayAmt);

    function liquidate(
        uint256 id,
        address liquidator,
        address treasurer,
        uint128 repayAmt
    ) external;

    function delivery(
        uint256 ratio,
        address to
    ) external returns (bytes memory deliveryData);
}
