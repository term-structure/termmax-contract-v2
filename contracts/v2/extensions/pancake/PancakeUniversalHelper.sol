// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Commands
/// @notice Command Flags used to decode commands
library Commands {
    // Masks to extract certain bits of commands
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;
    bytes1 internal constant COMMAND_TYPE_MASK = 0x3f;

    // Command Types. Maximum supported command at this moment is 0x3f.
    // The commands are executed in nested if blocks to minimise gas consumption

    // Command Types where value<=0x07, executed in the first nested-if block
    uint256 constant V3_SWAP_EXACT_IN = 0x00;
    uint256 constant V3_SWAP_EXACT_OUT = 0x01;
    uint256 constant PERMIT2_TRANSFER_FROM = 0x02;
    uint256 constant PERMIT2_PERMIT_BATCH = 0x03;
    uint256 constant SWEEP = 0x04;
    uint256 constant TRANSFER = 0x05;
    uint256 constant PAY_PORTION = 0x06;
    // COMMAND_PLACEHOLDER = 0x07;

    // Command Types where 0x08<=value<=0x0f, executed in the second nested-if block
    uint256 constant V2_SWAP_EXACT_IN = 0x08;
    uint256 constant V2_SWAP_EXACT_OUT = 0x09;
    uint256 constant PERMIT2_PERMIT = 0x0a;
    uint256 constant WRAP_ETH = 0x0b;
    uint256 constant UNWRAP_WETH = 0x0c;
    uint256 constant PERMIT2_TRANSFER_FROM_BATCH = 0x0d;
    uint256 constant BALANCE_CHECK_ERC20 = 0x0e;
    // COMMAND_PLACEHOLDER = 0x0f;

    // Command Types where 0x10<=value<=0x20, executed in the third nested-if block
    uint256 constant INFI_SWAP = 0x10;
    uint256 constant V3_POSITION_MANAGER_PERMIT = 0x11;
    uint256 constant V3_POSITION_MANAGER_CALL = 0x12;
    uint256 constant INFI_CL_INITIALIZE_POOL = 0x13;
    uint256 constant INFI_BIN_INITIALIZE_POOL = 0x14;
    uint256 constant INFI_CL_POSITION_CALL = 0x15;
    uint256 constant INFI_BIN_POSITION_CALL = 0x16;
    // COMMAND_PLACEHOLDER = 0x17 -> 0x20

    // Command Types where 0x21<=value<=0x3f
    uint256 constant EXECUTE_SUB_PLAN = 0x21;
    uint256 constant STABLE_SWAP_EXACT_IN = 0x22;
    uint256 constant STABLE_SWAP_EXACT_OUT = 0x23;
    // COMMAND_PLACEHOLDER = 0x24 -> 0x3f
}

interface IPancakeUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;
}

abstract contract PancakeUniversalHelper {
    function scale(uint256 realInput, address recipient, bytes memory swapData) internal pure returns (bytes memory) {
        bytes4 selector;
        assembly {
            selector := mload(add(swapData, 32))
        }
        require(selector == IPancakeUniversalRouter.execute.selector, "PancakeUniversalHelper: invalid selector");

        bytes memory dataToDecode;
        assembly {
            let len := sub(mload(swapData), 4)
            dataToDecode := mload(0x40)
            mstore(dataToDecode, len)
            let src := add(rawCallData, 36)
            let dest := add(dataToDecode, 32)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } { mstore(add(dest, i), mload(add(src, i))) }
            mstore(0x40, add(dest, len))
        }
        (bytes calldata commands, bytes[] calldata inputs, uint256 deadline) =
            abi.decode(dataToDecode, (bytes, bytes[], uint256));
        require(inputs.length == commands.length, "LengthMismatch");
        // loop scaling inputs
        for (uint256 commandIndex = 0; commandIndex < commands.length; commandIndex++) {
            uint256 command = uint8(commands[commandIndex] & Commands.COMMAND_TYPE_MASK);
            if (command == Commands.V3_SWAP_EXACT_IN) {} else if (command == Commands.V3_SWAP_EXACT_OUT) {} else if (
                command == Commands.V2_SWAP_EXACT_IN
            ) {} else if (command == Commands.V2_SWAP_EXACT_OUT) {} else if (command == Commands.INFI_SWAP) {} else if (
                command == Commands.STABLE_SWAP_EXACT_IN
            ) {} else if (command == Commands.STABLE_SWAP_EXACT_OUT) {}
        }
    }
}
