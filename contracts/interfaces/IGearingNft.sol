// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IGearingNft is IERC721 {
    error UnallowedUpgrade();

    function initialize(string memory name, string memory symbol) external;

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
        returns (address owner, uint128 debtAmt, bytes memory collateralData);

    function burn(uint256 id) external;

    function updateDebt(uint256 id, uint128 newDebtAmt) external;
}
