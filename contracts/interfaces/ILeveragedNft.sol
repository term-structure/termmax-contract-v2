// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ILeveragedNft is IERC721 {
    function marketAddr() external view returns (address);

    function collateralToken() external view returns (address);

    function debtToken() external view returns (address);

    function burn(uint256 id) external;
}
