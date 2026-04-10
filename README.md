## TermMax

**TermMax is a decentralized finance (DeFi) platform designed to simplify and enhance leveraged yield strategies. By integrating fixed-rate borrowing and lending mechanisms with leverage functions, TermMax enables investors to borrow at predictable fixed costs, earn expected returns, and maximize leveraged yields. This approach eliminates the need for multiple complex transactions across different protocols, making leveraged yield strategies more accessible, efficient, and profitable for all types of investors.**

## Documentation

TermMax Docs: https://docs.ts.finance/


## Bounty

Bounty plan: https://immunefi.com/bug-bounty/termstructurelabs/information/

### Install Dependencies
```shell
$ forge soldeer update
```

### Build

```shell
$ forge build
```

### Before test

You can find the `example.env` file at env folders, please copy it and put your env configuration in it.
Edit the `MAINNET_RPC_URL` value if you want to start fork tests.

### Test

Test without fork.

```shell
$ forge test --skip Fork
```

Using '--isolate' when testing TermMaxVault.

```shell
$ forge test --skip Fork --isolate
```

Using test scripts can configure multiple environments more flexibly, it will automatically configure the environment variables you need.
Do unit test if you have an env file named sepolia.env.

```shell
$ ./test.sh sepolia
```

You can use the forge test parameter as input.

```shell
$ ./test.sh sepolia --match-contract xxx -vv
```

### Deploy

```shell
$ forge script script/DeployScript.s.sol:FactoryScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Format

Install `esbenp.prettier-vscode` plugin for VsCode.
TermMax use Prettier to format codes. Install the plugin by yarn or npm tools.
Add configurations to your .vscode/settings.json

```json
  "files.autoSave": "onFocusChange",
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true,
  "[solidity]": {
    "editor.defaultFormatter": "NomicFoundation.hardhat-solidity"
  },
```

```shell
$ npm ci
```

## Gas Report

Below are gas-report summaries for key contracts. Use the overview table for deployment comparisons, then expand each contract section for per-function stats.

| Contract | Source | Deploy Cost | Deploy Size |
|---|---|---:|---:|
| TermMaxMarketV2 | contracts/v2/TermMaxMarketV2.sol | 3,342,898 | 15,520 |
| TermMaxOrderV2 | contracts/v2/TermMaxOrderV2.sol | 5,381,106 | 24,722 |
| MakerHelper | contracts/v2/router/MakerHelper.sol | 2,458,785 | 11,377 |
| TermMaxRouterV2 | contracts/v2/loader/TermMaxRouterV2.sol | 4,907,139 | 22,737 |
| GearingTokenWithERC20V2 | contracts/v2/tokens/GearingTokenWithERC20V2.sol | 5,096,680 | 23,407 |
| TermMaxVaultV2 | contracts/v2/vault/TermMaxVaultV2.sol | 4,736,478 | 22,022 |

<details>
<summary><strong>TermMaxMarketV2</strong> - contracts/v2/TermMaxMarketV2.sol</summary>

| Function | Min | Avg | Median | Max | Calls |
|---|---:|---:|---:|---:|---:|
| acceptOwnership | 12,313 | 12,313 | 12,313 | 12,313 | 25 |
| burn(address,address,uint256) | 8,152 | 44,110 | 40,097 | 88,097 | 4 |
| burn(address,uint256) | 27,602 | 69,503 | 71,602 | 87,902 | 2,225 |
| config | 1,838 | 4,215 | 3,838 | 5,838 | 10,113 |
| createOrder((address,address,address,address,address,uint256,address,uint64,(((uint256,uint256,int256)[],(uint256,uint256,int256)[]),uint256,uint256,address,(uint32,uint32,uint32,uint32,uint32,uint32)))) | 784,349 | 1,061,596 | 1,205,737 | 2,503,377 | 3,343 |
| createOrder(...,uint256) | 1,169,360 | 1,195,109 | 1,195,160 | 1,195,160 | 513 |
| createOrder(address,uint256,address,((uint256,uint256,int256)[],(uint256,uint256,int256)[])) | 6,900 | 1,152,335 | 1,159,950 | 1,159,950 | 153 |
| initialize | 75,027 | 960,040 | 961,469 | 961,469 | 2,422 |
| issueFt | 8,319 | 410,459 | 420,059 | 455,449 | 2,383 |
| issueFtByExistedGt | 7,661 | 149,196 | 147,330 | 201,430 | 518 |
| leverageByXt(address,address,uint128,bytes) | 482,882 | 514,448 | 531,682 | 531,682 | 515 |
| leverageByXt(address,uint128,bytes) | 8,237 | 512,271 | 510,301 | 531,901 | 515 |
| mint | 7,653 | 112,425 | 109,068 | 160,368 | 8,587 |
| mintGtFeeRatio | 1,052 | 5,045 | 5,052 | 5,052 | 1,804 |
| name | 2,786 | 2,786 | 2,786 | 2,786 | 1 |
| predictOrderAddress | 10,359 | 10,359 | 10,359 | 10,359 | 130 |
| previewRedeem | 47,220 | 47,220 | 47,220 | 47,220 | 1 |
| redeem(address,address,uint256) | 21,041 | 58,743 | 21,041 | 134,148 | 3 |
| redeem(uint256,address) | 99,075 | 110,526 | 116,175 | 127,380 | 761 |
| tokens | 5,245 | 11,236 | 11,245 | 11,245 | 4,259 |
| transferOwnership | 26,800 | 26,800 | 26,800 | 26,800 | 25 |
| updateGtConfig | 22,398 | 22,398 | 22,398 | 22,398 | 1 |
| updateMarketConfig | 2,590 | 15,061 | 3,424 | 34,423 | 5 |
| updateOrderFeeRate | 12,316 | 12,316 | 12,316 | 12,316 | 1 |

</details>

<details>
<summary><strong>TermMaxOrderV2</strong> - contracts/v2/TermMaxOrderV2.sol</summary>

| Function | Min | Avg | Median | Max | Calls |
|---|---:|---:|---:|---:|---:|
| addLiquidity | 35,437 | 126,353 | 126,890 | 147,024 | 133 |
| apr | 30,936 | 44,540 | 30,936 | 71,748 | 3 |
| borrowToken | 7,848 | 98,030 | 68,929 | 246,413 | 4 |
| getRealReserves | 19,927 | 27,849 | 28,322 | 35,427 | 60 |
| initialize | 715,363 | 1,012,118 | 1,134,172 | 2,424,027 | 3,948 |
| maker | 2,515 | 2,515 | 2,515 | 2,515 | 385 |
| market | 2,747 | 2,747 | 2,747 | 2,747 | 1 |
| orderConfig | 15,877 | 86,775 | 105,877 | 110,877 | 1,327 |
| orderExpiryTimestamp | 2,345 | 2,345 | 2,345 | 2,345 | 6 |
| owner | 2,823 | 2,823 | 2,823 | 2,823 | 2 |
| pause | 2,832 | 14,517 | 14,517 | 26,202 | 2 |
| paused | 2,635 | 2,635 | 2,635 | 2,635 | 2 |
| pool | 329 | 1,344 | 2,329 | 2,329 | 528 |
| redeemAll | 223,403 | 292,932 | 330,903 | 348,003 | 1,281 |
| removeLiquidity | 42,513 | 191,231 | 196,335 | 196,335 | 268 |
| setCurveAndPrice | 5,506 | 66,624 | 9,995 | 219,286 | 571 |
| setExpiryTimestamp | 2,774 | 21,028 | 23,730 | 23,730 | 10 |
| setGeneralConfig | 2,776 | 34,925 | 28,445 | 48,345 | 776 |
| setPool | 192,724 | 237,865 | 238,115 | 249,266 | 137 |
| swapExactTokenToToken | 8,012 | 310,958 | 351,422 | 500,659 | 2,122 |
| swapTokenToExactToken | 10,600 | 367,504 | 382,282 | 577,327 | 1,065 |
| unpause | 8,544 | 8,544 | 8,544 | 8,544 | 1 |
| updateFeeConfig | 3,297 | 3,297 | 3,297 | 3,298 | 2 |
| virtualXtReserve | 2,253 | 2,253 | 2,253 | 2,253 | 425 |
| withdrawAllAssetsBeforeMaturity | 115,430 | 155,346 | 141,091 | 172,700 | 256 |
| withdrawAssets | 23,640 | 32,652 | 38,082 | 40,740 | 7 |

</details>

<details>
<summary><strong>MakerHelper</strong> - contracts/v2/router/MakerHelper.sol</summary>

| Function | Min | Avg | Median | Max | Calls |
|---|---:|---:|---:|---:|---:|
| initialize | 50,700 | 50,700 | 50,700 | 50,700 | 6 |
| placeOrderForV1 | 16,220 | 895,925 | 895,925 | 1,775,630 | 2 |
| placeOrderForV2 | 21,208 | 909,579 | 840,178 | 1,883,573 | 1,024 |

</details>

<details>
<summary><strong>TermMaxRouterV2</strong> - contracts/v2/loader/TermMaxRouterV2.sol</summary>

| Function | Min | Avg | Median | Max | Calls |
|---|---:|---:|---:|---:|---:|
| acceptOwnership | 12,280 | 12,280 | 12,280 | 12,280 | 26 |
| borrowTokenFromCollateral | 958,476 | 958,476 | 958,476 | 958,476 | 1 |
| borrowTokenFromCollateralAndXt | 676,873 | 704,351 | 729,763 | 729,763 | 256 |
| executeOperation(address,address,uint256,bytes) | 75,401 | 106,526 | 116,901 | 116,901 | 1,024 |
| executeOperation(address,uint128,address,bytes,bytes) | 97,381 | 219,102 | 97,381 | 462,545 | 3 |
| flashRepayFromColl | 348,149 | 539,792 | 539,792 | 731,436 | 2 |
| flashRepayToGetCollateral | 348,747 | 348,747 | 348,747 | 348,747 | 1 |
| initialize | 75,674 | 75,674 | 75,674 | 75,674 | 48 |
| initializeV2 | 9,116 | 9,116 | 9,116 | 9,116 | 1 |
| leverage | 665,703 | 800,811 | 692,400 | 1,149,691 | 1,024 |
| onERC721Received | 766 | 766 | 766 | 766 | 260 |
| owner | 2,636 | 2,636 | 2,636 | 2,636 | 1 |
| pause | 2,645 | 20,172 | 26,015 | 26,015 | 4 |
| paused | 2,492 | 2,492 | 2,492 | 2,492 | 6 |
| proxiableUUID | 394 | 394 | 394 | 394 | 2 |
| swapAndRepay | 535,507 | 575,440 | 575,440 | 615,374 | 2 |
| swapTokens | 49,878 | 434,353 | 585,691 | 805,103 | 7 |
| transferOwnership | 26,811 | 26,811 | 26,811 | 26,811 | 26 |
| unpause | 8,561 | 8,561 | 8,561 | 8,561 | 3 |
| upgradeToAndCall | 10,925 | 15,667 | 15,667 | 20,410 | 2 |

</details>

<details>
<summary><strong>GearingTokenWithERC20V2</strong> - contracts/v2/tokens/GearingTokenWithERC20V2.sol</summary>

| Function | Min | Avg | Median | Max | Calls |
|---|---:|---:|---:|---:|---:|
| DOMAIN_SEPARATOR | 6,019 | 6,019 | 6,019 | 6,019 | 267 |
| addCollateral | 8,925 | 33,653 | 46,018 | 46,018 | 3 |
| approve | 26,874 | 26,874 | 26,874 | 26,874 | 7 |
| augmentDebt | 94,078 | 96,989 | 96,878 | 113,978 | 517 |
| balanceOf | 3,040 | 3,040 | 3,040 | 3,040 | 7 |
| collateralCapacity | 3,188 | 3,188 | 3,188 | 3,188 | 1 |
| delivery | 34,011 | 34,084 | 34,011 | 45,216 | 762 |
| flashRepay(uint256,bool,bytes) | 199,751 | 327,401 | 199,751 | 582,702 | 3 |
| flashRepay(uint256,uint128,bool,bytes,bytes) | 17,698 | 100,053 | 102,745 | 177,023 | 4 |
| getGtConfig | 12,841 | 12,841 | 12,841 | 12,841 | 3 |
| getLiquidationInfo | 14,390 | 14,913 | 14,390 | 82,162 | 1,033 |
| initialize | 25,189 | 331,884 | 332,138 | 332,138 | 2,419 |
| isDelegate | 3,039 | 3,039 | 3,039 | 3,039 | 145 |
| liquidatable | 3,049 | 3,049 | 3,049 | 3,049 | 765 |
| liquidate | 54,631 | 177,626 | 183,905 | 248,958 | 526 |
| loanInfo | 2,374 | 7,187 | 10,374 | 10,374 | 2,596 |
| merge | 23,630 | 77,856 | 87,888 | 148,457 | 5 |
| mint | 28,085 | 337,956 | 337,059 | 349,159 | 3,411 |
| nonces | 3,058 | 3,058 | 3,058 | 3,058 | 284 |
| ownerOf | 2,984 | 2,984 | 2,984 | 2,984 | 1 |
| previewDelivery | 8,791 | 8,791 | 8,791 | 8,791 | 1 |
| removeCollateral | 10,984 | 66,785 | 66,608 | 131,569 | 264 |
| repay | 17,374 | 87,770 | 82,818 | 149,607 | 12 |
| repayAndRemoveCollateral | 11,433 | 92,963 | 94,239 | 177,368 | 265 |
| safeTransferFrom(address,address,uint256) | 52,432 | 52,432 | 52,432 | 52,432 | 257 |
| safeTransferFrom(address,address,uint256,bytes) | 7,275 | 67,865 | 76,259 | 76,871 | 8 |
| setDelegate | 702 | 20,720 | 24,894 | 24,894 | 27 |
| setDelegateWithSignature | 953 | 54,821 | 57,205 | 57,205 | 139 |
| setTreasurer | 7,975 | 7,975 | 7,975 | 7,975 | 2 |
| tokenOfOwnerByIndex | 3,079 | 3,079 | 3,079 | 3,079 | 1 |
| totalSupply | 2,422 | 2,422 | 2,422 | 2,422 | 256 |
| updateConfig | 11,241 | 11,241 | 11,241 | 11,241 | 1 |

</details>

<details>
<summary><strong>TermMaxVaultV2</strong> - contracts/v2/vault/TermMaxVaultV2.sol</summary>

| Function | Min | Avg | Median | Max | Calls |
|---|---:|---:|---:|---:|---:|
| acceptGuardian | 3,706 | 9,969 | 13,101 | 13,101 | 3 |
| acceptMarket | 4,436 | 41,849 | 42,111 | 42,111 | 144 |
| acceptPendingMinApy | 2,504 | 7,234 | 7,238 | 11,955 | 4 |
| acceptPerformanceFeeRate | 29,506 | 29,506 | 29,506 | 29,506 | 1 |
| acceptPool | 8,948 | 121,383 | 139,148 | 198,288 | 4 |
| acceptTimelock | 3,384 | 8,072 | 8,076 | 12,751 | 4 |
| accretingPrincipal | 12,304 | 12,304 | 12,304 | 12,304 | 1 |
| afterSwap | 4,129 | 166,375 | 206,501 | 255,413 | 30 |
| annualizedInterest | 4,138 | 4,138 | 4,138 | 4,138 | 13 |
| approve | 24,458 | 24,458 | 24,458 | 24,458 | 1 |
| apy | 7,108 | 7,108 | 7,108 | 7,108 | 14 |
| badDebtMapping | 3,111 | 3,111 | 3,111 | 3,111 | 8 |
| balanceOf | 3,255 | 3,255 | 3,255 | 3,255 | 11 |
| createOrder | 15,505 | 1,289,631 | 1,278,011 | 1,312,411 | 1,119 |
| curator | 4,176 | 4,176 | 4,176 | 4,176 | 3 |
| dealBadDebt | 8,666 | 55,126 | 54,485 | 87,090 | 12 |
| deposit | 77,866 | 181,614 | 158,663 | 266,018 | 79 |
| guardian | 2,855 | 2,855 | 2,855 | 2,855 | 4 |
| initialize | 246,103 | 286,475 | 285,903 | 319,691 | 87 |
| marketWhitelist | 2,705 | 2,705 | 2,705 | 2,705 | 5 |
| minApy | 2,636 | 2,636 | 2,636 | 2,636 | 5 |
| pause | 26,690 | 27,620 | 26,690 | 28,862 | 7 |
| paused | 2,983 | 2,983 | 2,983 | 2,983 | 2 |
| pendingGuardian | 3,579 | 3,579 | 3,579 | 3,579 | 1 |
| pendingMarkets | 3,406 | 3,406 | 3,406 | 3,406 | 2 |
| pendingMinApy | 4,378 | 4,378 | 4,378 | 4,378 | 19 |
| pendingPerformanceFeeRate | 3,146 | 3,146 | 3,146 | 3,146 | 1 |
| pendingPool | 4,173 | 4,173 | 4,173 | 4,173 | 18 |
| pendingTimelock | 3,630 | 3,630 | 3,630 | 3,630 | 2 |
| performanceFeeRate | 2,454 | 2,454 | 2,454 | 2,454 | 2 |
| pool | 2,526 | 2,526 | 2,526 | 2,526 | 3 |
| previewDeposit | 11,188 | 12,839 | 11,188 | 16,143 | 6 |
| previewRedeem | 14,823 | 16,675 | 14,823 | 19,455 | 15 |
| previewWithdraw | 13,838 | 14,061 | 13,838 | 14,360 | 7 |
| redeem | 83,527 | 105,735 | 107,128 | 130,730 | 12 |
| redeemOrder | 259,100 | 329,255 | 261,238 | 476,130 | 1,030 |
| removeLiquidityFromOrders | 173,063 | 209,636 | 209,636 | 246,210 | 4 |
| revokePendingGuardian | 8,739 | 9,825 | 9,825 | 10,911 | 2 |
| revokePendingMarket | 10,816 | 11,902 | 11,902 | 12,988 | 2 |
| revokePendingMinApy | 5,517 | 8,984 | 9,465 | 11,637 | 5 |
| revokePendingPerformanceFeeRate | 9,421 | 9,421 | 9,421 | 9,421 | 1 |
| revokePendingPool | 5,231 | 7,908 | 8,551 | 11,351 | 5 |
| revokePendingTimelock | 10,081 | 11,167 | 11,167 | 12,253 | 2 |
| setCurator | 10,588 | 10,588 | 10,588 | 10,588 | 4 |
| submitGuardian | 3,735 | 22,005 | 30,953 | 32,145 | 8 |
| submitMarket | 4,811 | 42,545 | 44,235 | 44,235 | 151 |
| submitPendingMinApy | 5,636 | 18,566 | 12,366 | 31,760 | 19 |
| submitPendingPool | 5,105 | 30,157 | 42,155 | 68,252 | 12 |
| submitPerformanceFeeRate | 5,983 | 20,292 | 28,791 | 32,196 | 9 |
| submitTimelock | 5,327 | 16,594 | 11,975 | 29,331 | 13 |
| timelock | 3,998 | 3,998 | 3,998 | 3,998 | 6 |
| totalAssets | 6,677 | 11,554 | 11,632 | 16,264 | 30 |
| totalFt | 3,038 | 3,038 | 3,038 | 3,038 | 12 |
| totalSupply | 2,553 | 2,553 | 2,553 | 2,553 | 10 |
| unpause | 8,928 | 9,362 | 8,928 | 11,100 | 5 |
| updateOrdersConfiguration | 342,779 | 342,779 | 342,779 | 342,779 | 4 |
| withdraw | 68,513 | 96,190 | 95,601 | 125,048 | 4 |
| withdrawFts | 23,132 | 72,229 | 71,432 | 122,923 | 4 |

</details>

