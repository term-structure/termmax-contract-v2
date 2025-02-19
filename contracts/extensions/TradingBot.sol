// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFlashLoanAave, IAaveFlashLoanCallback} from "./IFlashLoanAave.sol";
import {IFlashLoanMorpho, IMorphoFlashLoanCallback} from "./IFlashLoanMorpho.sol";

contract TradingBot is IAaveFlashLoanCallback, IMorphoFlashLoanCallback {

    address immutable AAVE_POOL;
    address immutable AAVE_ADDRESSES_PROVIDER;
    
    constructor(address _AAVE_POOL, address _AAVE_ADDRESSES_PROVIDER){
        AAVE_POOL = _AAVE_POOL;
        AAVE_ADDRESSES_PROVIDER = _AAVE_ADDRESSES_PROVIDER;
    }
    

    /// @notice morpho callback
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {}

    /// @notice aave callback
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {}

    function ADDRESSES_PROVIDER() external view returns (address){
        return AAVE_ADDRESSES_PROVIDER;
    }

    function POOL() external view returns (IFlashLoanAave){
        return AAVE_POOL;
    }
}
