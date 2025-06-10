// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PendingAddress, PendingUint192} from "../../v1/lib/PendingLib.sol";

interface ITermMaxVaultV2 {
    /// @notice Returns the apr based on accreting principal
    function apy() external view returns (uint256);

    function minApy() external view returns (uint64);

    function minIdleFundRate() external view returns (uint64);

    function pendingMinApy() external view returns (PendingUint192 memory);
    function pendingMinIdleFundRate() external view returns (PendingUint192 memory);

    function submitPendingMinApy(uint64 newMinApy) external;
    function submitPendingMinIdleFundRate(uint64 newMinIdleFundRate) external;

    function acceptPendingMinApy() external;
    function acceptPendingMinIdleFundRate() external;

    function revokePendingMinApy() external;
    function revokePendingMinIdleFundRate() external;
}
