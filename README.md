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
$ yarn
```
