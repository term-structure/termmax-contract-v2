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
            uint128 health,
            bytes memory collateralData
        );

    function calculateHealth(
        uint256 debtAmt,
        bytes memory collateralData
    ) external view returns (uint128 health, uint256 collateralValue);

    function merge(uint256[] memory ids) external returns (uint256 newId);

    function repay(address sender, uint256 id, uint128 repayAmt) external;

    function removeCollateral(uint256 id, bytes memory collateralData) external;

    function liquidate(
        uint256 id,
        address liquidator,
        address treasurer,
        uint64 maturity
    ) external returns (uint128 debtAmt);

    function delivery(
        uint256 ratio,
        address to
    ) external returns (bytes memory deliveryData);
}
