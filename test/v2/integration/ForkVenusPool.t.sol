// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {StableERC4626ForVenus, IVToken} from "contracts/v2/tokens/StableERC4626ForVenus.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC4626TokenErrors} from "contracts/v2/errors/ERC4626TokenErrors.sol";
import {ForkBaseTestV2, IERC20, IERC20Metadata} from "../mainnet-fork/ForkBaseTestV2.sol";
import {console} from "forge-std/console.sol";

contract ForkVenusPool is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    IVToken[] public vTokens;
    IERC20[] public underlyings;
    StableERC4626ForVenus[] public venusPools;
    address public admin = vm.randomAddress();

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        IVToken vUSD1 = IVToken(0x0C1DA220D301155b87318B90692Da8dc43B67340);
        IERC20 underlyingUSD1 = IERC20(vUSD1.underlying());
        vTokens.push(vUSD1);
        underlyings.push(underlyingUSD1);
        venusPools.push(_deployVenusPool(address(vUSD1), address(underlyingUSD1)));
    }

    function _deployVenusPool(address vToken, address underlying) internal returns (StableERC4626ForVenus) {
        // Setup default buffer scaled by underlying decimals
        uint8 underlyingDecimals = IERC20Metadata(underlying).decimals();
        uint256 scale = 10 ** underlyingDecimals;
        uint256 minBuf = 1000 * scale;
        uint256 maxBuf = 10000 * scale;
        uint256 buf = 5000 * scale;

        address implementation = address(new StableERC4626ForVenus());
        StableERC4626ForVenus venusPool = StableERC4626ForVenus(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        StableERC4626ForVenus.initialize.selector,
                        admin,
                        vToken,
                        StakingBuffer.BufferConfig({minimumBuffer: minBuf, maximumBuffer: maxBuf, buffer: buf})
                    )
                )
            )
        );
        return venusPool;
    }

    function testDepositWithdrawAndIncome() public {
        for (uint256 i = 0; i < venusPools.length; i++) {
            StableERC4626ForVenus pool = venusPools[i];
            IERC20 underlying = underlyings[i];

            uint256 decimals = IERC20Metadata(address(underlying)).decimals();
            // Deposit amount > maxBuffer (10000 * 10**decimals)
            // maxBuffer is set to 10000 * 10**decimals in _deployVenusPool
            uint256 depositAmount = 20000 * 10 ** decimals;

            address user = address(0x123456);
            deal(address(underlying), user, depositAmount);

            vm.startPrank(user);
            underlying.approve(address(pool), depositAmount);
            pool.deposit(depositAmount, user);
            vm.stopPrank();

            assertEq(pool.balanceOf(user), depositAmount, "User shares should match deposit");
            assertEq(pool.totalSupply(), depositAmount, "Total supply should match deposit");

            // Simulate income: transfer tokens to pool directly
            uint256 incomeAmount = 500 * 10 ** decimals;
            deal(address(underlying), address(user), incomeAmount);
            vm.prank(user);
            underlying.transfer(address(pool), incomeAmount);

            uint256 totalIncome = pool.totalIncomeAssets();
            assertApproxEqAbs(totalIncome, incomeAmount, 1e16, "Total income should match donated amount");

            // Withdraw income
            address recipient = address(0x789);
            uint256 preBalance = underlying.balanceOf(recipient);

            vm.prank(admin);
            pool.withdrawIncomeAssets(address(underlying), recipient, incomeAmount - 1e16);

            uint256 postBalance = underlying.balanceOf(recipient);
            assertEq(postBalance - preBalance, incomeAmount - 1e16, "Recipient should receive income");

            // User withdraws all
            vm.startPrank(user);
            pool.withdraw(depositAmount, user, user);
            vm.stopPrank();

            assertEq(underlying.balanceOf(user), depositAmount, "User should get back principal");
            assertEq(pool.totalSupply(), 0, "Pool should be empty");
        }
    }
}
