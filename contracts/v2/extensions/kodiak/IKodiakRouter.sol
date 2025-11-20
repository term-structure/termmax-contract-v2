// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IKodiakRouter {
    // @dev The amount of tokens to swap
    // @dev This token will be taken from the sender, which means this data can be trusted
    struct InputAmount {
        address token;
        bool wrap;
        uint256 amount;
    }

    // @dev The minimum amount of tokens to receive after the swap
    // @dev Use only in defense of the sender's interests, but cannot be trusted as the user can spoof this
    struct OutputAmount {
        address token;
        bool unwrap;
        uint256 minAmountOut;
        address receiver;
    }

    // @dev quote used for surplus fee (eg Kodiak quote, OB quote)
    // @dev optional fee on surplus
    // @dev referral code
    // @dev referral fee in bps
    struct FeeData {
        uint256 feeQuote;
        uint16 surplusFeeBps;
        uint16 refCode;
        uint16 referrerFeeBps;
    }

    struct SwapData {
        address router;
        bytes data;
    }

    function swap(
        InputAmount calldata input,
        OutputAmount calldata output,
        SwapData calldata swapData,
        FeeData calldata feeData
    ) external payable;
}
