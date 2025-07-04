// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract TransactionReentrancyGuard {
    /// @notice Error thrown when a reentrant call is detected in one transaction.
    error ReentrantCall();
    /// @notice Error thrown when a reentrant call is detected between actions.
    error ReentrantCallBetweenActions(uint256 actionId, uint256 oldActionId);
    /// @notice Error thrown when using reserved ID. (0 and 1 are reserved id)
    error InvalidActionId();

    // keccak256(abi.encode(uint256(keccak256("termmax.tsstorage.TransactionReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    uint256 private constant T_FLAG_STORE = 0x55d65f3b5821c66716708cd5119fc8b654f479bd23b96d0911cee85241904700;

    /// @notice Modifier to prevent reentrant calls in one transaction.
    modifier nonTxReentrant() {
        if (_getTxReentrancyGuardStorage() == 1) revert ReentrantCall();
        _setTxReentrancyGuardStorage(1);
        _;
    }

    modifier nonTxReentrantBetweenActions(uint256 actionId) {
        if (actionId <= 1) revert InvalidActionId();
        uint256 oldActionId = _getTxReentrancyGuardStorage();
        if (oldActionId != 0 && oldActionId != actionId) revert ReentrantCallBetweenActions(actionId, oldActionId);
        _setTxReentrancyGuardStorage(actionId);
        _;
    }

    function _getTxReentrancyGuardStorage() private view returns (uint256 reentrancyGuard) {
        assembly {
            reentrancyGuard := tload(T_FLAG_STORE)
        }
    }

    function _setTxReentrancyGuardStorage(uint256 reentrancyGuard) private {
        assembly {
            tstore(T_FLAG_STORE, reentrancyGuard)
        }
    }
}
