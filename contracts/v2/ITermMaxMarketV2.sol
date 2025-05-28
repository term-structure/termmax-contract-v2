// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TermMax Market V2 interface
 * @author Term Structure Labs
 */
interface ITermMaxMarketV2 {
    function name() external view returns (string memory);

    function burn(address owner, address recipient, uint256 debtTokenAmt) external;

    function leverageByXt(address xtOwner, address recipient, uint128 xtAmt, bytes calldata callbackData)
        external
        returns (uint256 gtId);

    function redeem(address ftOwner, address recipient, uint256 ftAmount) external returns (uint256, bytes memory);
}
