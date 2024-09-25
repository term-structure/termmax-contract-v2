// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

struct InitalData {
    uint16 interest;
    uint16 feeRate;
    /// debt to collateral 90%
    uint16 lvt;
}
interface IYAMarketFactory{
    function create(address collateralToken, address debtToken, uint64 maturity, InitalData calldata initalData) external returns(address);

    /// @notice key = keccak256(abi.encode(collateralToken, debtToken, maturity))
    function marketAddress(bytes32 key) external returns(address);
}