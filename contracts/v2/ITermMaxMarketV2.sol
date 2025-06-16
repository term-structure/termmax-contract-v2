// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderConfig} from "../v1/storage/TermMaxStorage.sol";
import {ITermMaxOrder} from "../v1/ITermMaxOrder.sol";

/**
 * @title TermMax Market V2 interface
 * @author Term Structure Labs
 * @notice Interface for TermMax V2 markets with enhanced functionality over V1
 * @dev Extends the base market functionality with additional features for better user experience
 */
interface ITermMaxMarketV2 {
    /**
     * @notice Returns the human-readable name of the market
     * @dev Used for identification and display purposes in V2 markets
     * @return The name string of the market (e.g., "Termmax Market:USDC-24-Dec")
     */
    function name() external view returns (string memory);

    /**
     * @notice Burns FT and XT tokens on behalf of an owner to redeem underlying tokens
     * @dev V2 enhancement allowing third-party burning with proper authorization
     * @param owner The address that owns the tokens to be burned
     * @param recipient The address that will receive the redeemed underlying tokens
     * @param debtTokenAmt The amount of debt tokens (FT/XT pairs) to burn
     */
    function burn(address owner, address recipient, uint256 debtTokenAmt) external;

    /**
     * @notice Creates a leveraged position using XT tokens from a specified owner
     * @dev V2 enhancement allowing leverage creation on behalf of another address
     * @param xtOwner The address that owns the XT tokens to be used for leverage
     * @param recipient The address that will receive the generated GT (Gearing Token)
     * @param xtAmt The amount of XT tokens to use for creating the leveraged position
     * @param callbackData Encoded data passed to the flash loan callback for collateral handling
     * @return gtId The ID of the newly minted Gearing Token representing the leveraged position
     */
    function leverageByXt(address xtOwner, address recipient, uint128 xtAmt, bytes calldata callbackData)
        external
        returns (uint256 gtId);

    /**
     * @notice Redeems FT tokens on behalf of an owner after market maturity
     * @dev V2 enhancement allowing third-party redemption with proper authorization
     * @param ftOwner The address that owns the FT tokens to be redeemed
     * @param recipient The address that will receive the redeemed assets
     * @param ftAmount The amount of FT tokens to redeem
     * @return debtTokenAmt The amount of underlying debt tokens received
     * @return deliveryData Encoded data containing collateral delivery information
     */
    function redeem(address ftOwner, address recipient, uint256 ftAmount) external returns (uint256, bytes memory);

    function createOrder(address maker, OrderConfig memory orderconfig) external returns (ITermMaxOrder order);
}
