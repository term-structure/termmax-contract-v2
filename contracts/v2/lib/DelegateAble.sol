// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract DelegateAble {
    /**
     * @notice Authorization structure for delegation
     * @param delegator the address of the delegator
     * @param delegatee the address can use the delegation
     * @param isDelegate whether the delegate relationship is being established (true) or removed (false)
     * @param nonce the nonce of the delegator
     * @param deadline the deadline timestamp, type(uint256).max for max deadline
     */
    struct DelegateParameters {
        address delegator;
        address delegatee;
        bool isDelegate;
        uint256 nonce;
        uint256 deadline;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Error thrown when a delegatee tries to delegate to themselves
    error CannotDelegateToSelf();
    /// @notice Error thrown when a caller is not the delegatee
    error CallerIsNotDelegatee(address delegatee, address caller);
    /// @notice Error thrown when a signature is invalid
    error InvalidSignature();
    /// @notice Event emitted when a delegate relationship is established or removed
    /// @param delegator The address of the delegator
    /// @param delegatee The address of the delegatee
    /// @param isDelegate Indicates whether the delegate relationship is being established (true) or removed

    event DelegateChanged(address indexed delegator, address indexed delegatee, bool isDelegate);

    bytes32 public constant DELEGATION_WITH_SIG_TYPEHASH = keccak256(
        "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
    );

    /// @notice Mapping relationship between delegator and delegatee
    mapping(address => mapping(address => bool)) internal _delegateMapping;

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32);

    function isDelegate(address delegator, address delegatee) public view virtual returns (bool);

    function setDelegate(address delegatee, bool isDelegate_) external virtual {
        if (msg.sender == delegatee) {
            revert CannotDelegateToSelf();
        }
        _setDelegate(msg.sender, delegatee, isDelegate_);
    }

    function _setDelegate(address delegator, address delegatee, bool isDelegate_) internal virtual {
        if (!isDelegate_) {
            delete _delegateMapping[delegator][delegatee];
        } else {
            _delegateMapping[delegator][delegatee] = isDelegate_;
        }
        emit DelegateChanged(delegator, delegatee, isDelegate_);
    }

    function setDelegateWithSignature(DelegateParameters memory params, Signature memory signature) external virtual {
        if (msg.sender != params.delegatee) {
            revert CallerIsNotDelegatee(params.delegatee, msg.sender);
        }
        _checkSignature(params, signature);
        _setDelegate(params.delegator, params.delegatee, params.isDelegate);
    }

    function _checkSignature(DelegateParameters memory params, Signature memory signature) internal view {
        bytes32 digest = getTypedDataHash(params);
        address recoveredAddress = ecrecover(digest, signature.v, signature.r, signature.s);
        require(recoveredAddress == params.delegator, InvalidSignature());
    }

    function getTypedDataHash(DelegateParameters memory params) internal view returns (bytes32) {
        return keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct(params)));
    }

    function hashStruct(DelegateParameters memory params) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DELEGATION_WITH_SIG_TYPEHASH,
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
    }

    function updateNonce(address delegator) internal virtual;
}
