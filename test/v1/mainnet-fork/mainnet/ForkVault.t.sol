// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../VaultBaseTest.t.sol";

contract ForkVault is VaultBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testDeposit() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            VaultTestRes memory res = _initializeVaultTestRes(tokenPair);
            _testDeposit(res);
        }
    }

    function testRedeem() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            VaultTestRes memory res = _initializeVaultTestRes(tokenPair);
            _testRedeem(res);
        }
    }

    function testBadDebt() public {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            string memory tokenPair = tokenPairs[i];
            VaultTestRes memory res = _initializeVaultTestRes(tokenPair);
            _testBadDebt(res);
        }
    }
}
