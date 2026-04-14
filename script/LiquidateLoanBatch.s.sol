// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITermMaxMarketLike {
    function tokens()
        external
        view
        returns (address ft, address xt, address gt, address collateral, address underlying);
}

interface IGearingTokenLike {
    function loanInfo(uint256 id) external view returns (address owner, uint128 debtAmt, bytes memory collateralData);
    function getLiquidationInfo(uint256 id)
        external
        view
        returns (bool isLiquidable, uint128 ltv, uint128 maxRepayAmt);
    function liquidate(uint256 id, uint128 repayAmt, bool byDebtToken) external;
}

contract LiquidateLoanBatch is Script {
    uint256 deployerPrivateKey;
    address liquidator;

    struct LoanTask {
        address marketAddress;
        uint256 loanId;
    }

    function setUp() public {
        string memory network = vm.envString("NETWORK");
        string memory networkUpper = _networkToEnvPrefix(network);
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        liquidator = vm.addr(deployerPrivateKey);
    }

    function run() external {
        LoanTask[] memory tasks = _buildLoanTasks();

        console2.log("Total tasks:", tasks.length);
        console2.log("Liquidator:", liquidator);

        vm.startBroadcast(deployerPrivateKey);

        uint256 successCount = 0;
        uint256 skippedCount = 0;

        for (uint256 i = 0; i < tasks.length; i++) {
            LoanTask memory task = tasks[i];
            console2.log("==============================");
            console2.log("Task index:", i);
            console2.log("Market:", task.marketAddress);
            console2.log("LoanId:", task.loanId);

            (,, address marketGt,, address underlying) = ITermMaxMarketLike(task.marketAddress).tokens();

            address actualOwner;
            uint128 debtAmt;
            try IGearingTokenLike(marketGt).loanInfo(task.loanId) returns (
                address owner, uint128 onchainDebtAmt, bytes memory
            ) {
                actualOwner = owner;
                debtAmt = onchainDebtAmt;
            } catch {
                console2.log("Skip: loanInfo reverted");
                skippedCount++;
                continue;
            }

            if (debtAmt == 0) {
                console2.log("Skip: debt already zero");
                skippedCount++;
                continue;
            }

            bool isLiquidable;
            uint128 maxRepayAmtNow;
            try IGearingTokenLike(marketGt).getLiquidationInfo(task.loanId) returns (
                bool liquidable, uint128, uint128 maxRepayAmt
            ) {
                isLiquidable = liquidable;
                maxRepayAmtNow = maxRepayAmt;
            } catch {
                console2.log("Skip: getLiquidationInfo reverted");
                skippedCount++;
                continue;
            }

            if (!isLiquidable || maxRepayAmtNow == 0) {
                console2.log("Skip: no longer liquidable");
                skippedCount++;
                continue;
            }

            uint128 repayAmt = uint128(maxRepayAmtNow);
            uint256 bal = IERC20(underlying).balanceOf(liquidator);
            if (bal < repayAmt) {
                console2.log("Skip: insufficient debt token balance");
                console2.log("Underlying:", underlying);
                console2.log("Need:", repayAmt);
                console2.log("Have:", bal);
                skippedCount++;
                continue;
            }

            uint256 allowance = IERC20(underlying).allowance(liquidator, marketGt);
            if (allowance < repayAmt) {
                IERC20(underlying).approve(marketGt, type(uint256).max);
            }

            try IGearingTokenLike(marketGt).liquidate(task.loanId, repayAmt, true) {
                console2.log("Success: liquidated loan");
                console2.log("RepayAmt:", repayAmt);
                successCount++;
            } catch {
                console2.log("Failed: liquidate reverted");
                skippedCount++;
            }
        }

        vm.stopBroadcast();

        console2.log("==============================");
        console2.log("Liquidation finished");
        console2.log("Success:", successCount);
        console2.log("Skipped/Failed:", skippedCount);
    }

    function _networkToEnvPrefix(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 97 && c <= 122) {
                b[i] = bytes1(c - 32);
            } else if (c == 45) {
                b[i] = bytes1(uint8(95));
            }
        }
        return string(b);
    }

    function _buildLoanTasks() internal pure returns (LoanTask[] memory tasks) {
        tasks = new LoanTask[](10);

        for (uint256 i = 0; i < 10; i++) {
            tasks[i] = LoanTask({marketAddress: 0x47ae790a999263bF8F3ED95eAD318d6397036D39, loanId: 2 + i});
        }
    }
}
