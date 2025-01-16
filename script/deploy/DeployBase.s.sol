// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "../../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../../contracts/router/ITermMaxRouter.sol";
import {TermMaxMarket} from "../../contracts/TermMaxMarket.sol";
import {TermMaxOrder} from "../../contracts/TermMaxOrder.sol";
import {MockERC20} from "../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {IMintableERC20, MintableERC20} from "../../contracts/tokens/MintableERC20.sol";
import {SwapAdapter} from "../../contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "../../contracts/test/testnet/Faucet.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {FaucetERC20} from "../../contracts/test/testnet/FaucetERC20.sol";
import {IOracle, OracleAggregator} from "../../contracts/oracle/OracleAggregator.sol";
import {MarketConfig, FeeConfig, MarketInitialParams, LoanConfig} from "../../contracts/storage/TermMaxStorage.sol";

contract DeployBase is Script {
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    function deployFactory(address admin) public returns (TermMaxFactory factory) {
        address tokenImplementation = address(new MintableERC20());
        address orderImplementation = address(new TermMaxOrder());
        TermMaxMarket m = new TermMaxMarket(tokenImplementation, orderImplementation);
        factory = new TermMaxFactory(admin, address(m));
    }

    function deployOracleAggregator(address admin) public returns (OracleAggregator oracle) {
        OracleAggregator implementation = new OracleAggregator();
        bytes memory data = abi.encodeCall(OracleAggregator.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        oracle = OracleAggregator(address(proxy));
    }

    function deployRouter(address admin) public returns (TermMaxRouter router) {
        TermMaxRouter implementation = new TermMaxRouter();
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouter(address(proxy));
    }

    function deployCore(
        address adminAddr
    )
        public
        returns (
            TermMaxFactory factory,
            OracleAggregator oracleAggregator,
            TermMaxRouter router,
            SwapAdapter swapAdapter,
            Faucet faucet
        )
    {
        // deploy factory
        factory = deployFactory(adminAddr);

        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(adminAddr);

        // deploy router
        router = deployRouter(adminAddr);

        // deploy swap adapter
        swapAdapter = new SwapAdapter(adminAddr);
        router.setAdapterWhitelist(address(swapAdapter), true);

        // deploy faucet
        faucet = new Faucet(adminAddr);
    }

    function deployMarkets(
        address factoryAddr,
        address oracleAddr,
        address routerAddr,
        address faucetAddr,
        string memory deployDataPath,
        address adminAddr,
        address priceFeedOperatorAddr,
        uint64 openTimeDelay
    ) public returns (TermMaxMarket[] memory markets) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        IOracle oracle = IOracle(oracleAddr);
        ITermMaxRouter router = ITermMaxRouter(routerAddr);
        Faucet faucet = Faucet(faucetAddr);

        string memory deployData = vm.readFile(deployDataPath);

        JsonLoader.Config[] memory configs = JsonLoader.getConfigsFromJson(deployData);

        markets = new TermMaxMarket[](configs.length);

        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            // deploy underlying & collateral
            bytes32 tokenKey = faucet.calcTokenKey(
                config.collateralConfig.name,
                config.collateralConfig.symbol,
                config.collateralConfig.decimals
            );
            uint256 tokenId = faucet.getTokenIdByKey(tokenKey);
            FaucetERC20 collateral;
            MockPriceFeed collateralPriceFeed;
            FaucetERC20 underlying;
            MockPriceFeed underlyingPriceFeed;
            if (tokenId == 0) {
                (collateral, collateralPriceFeed) = faucet.addToken(
                    config.collateralConfig.name,
                    config.collateralConfig.symbol,
                    config.collateralConfig.decimals
                );

                collateralPriceFeed.updateRoundData(
                    MockPriceFeed.RoundData({
                        roundId: 1,
                        answer: config.collateralConfig.initialPrice,
                        startedAt: block.timestamp,
                        updatedAt: block.timestamp,
                        answeredInRound: 1
                    })
                );
                collateralPriceFeed.transferOwnership(priceFeedOperatorAddr);
            } else {
                collateral = FaucetERC20(faucet.getTokenConfig(tokenId).tokenAddr);
                collateralPriceFeed = MockPriceFeed(faucet.getTokenConfig(tokenId).priceFeedAddr);
            }

            tokenKey = faucet.calcTokenKey(
                config.underlyingConfig.name,
                config.underlyingConfig.symbol,
                config.underlyingConfig.decimals
            );
            tokenId = faucet.getTokenIdByKey(tokenKey);
            if (tokenId == 0) {
                (underlying, underlyingPriceFeed) = faucet.addToken(
                    config.underlyingConfig.name,
                    config.underlyingConfig.symbol,
                    config.underlyingConfig.decimals
                );

                underlyingPriceFeed.updateRoundData(
                    MockPriceFeed.RoundData({
                        roundId: 1,
                        answer: config.underlyingConfig.initialPrice,
                        startedAt: block.timestamp,
                        updatedAt: block.timestamp,
                        answeredInRound: 1
                    })
                );
                underlyingPriceFeed.transferOwnership(priceFeedOperatorAddr);
            } else {
                underlying = FaucetERC20(faucet.getTokenConfig(tokenId).tokenAddr);
                underlyingPriceFeed = MockPriceFeed(faucet.getTokenConfig(tokenId).priceFeedAddr);
            }

            MarketConfig memory marketConfig = MarketConfig({
                treasurer: config.marketConfig.treasurer,
                maturity: config.marketConfig.maturity,
                openTime: uint64(vm.getBlockTimestamp() + openTimeDelay),
                feeConfig: FeeConfig({
                    lendTakerFeeRatio: config.marketConfig.feeConfig.lendTakerFeeRatio,
                    lendMakerFeeRatio: config.marketConfig.feeConfig.lendMakerFeeRatio,
                    borrowTakerFeeRatio: config.marketConfig.feeConfig.borrowTakerFeeRatio,
                    borrowMakerFeeRatio: config.marketConfig.feeConfig.borrowMakerFeeRatio,
                    issueFtFeeRatio: config.marketConfig.feeConfig.issueFtFeeRatio,
                    issueFtFeeRef: config.marketConfig.feeConfig.issueFtFeeRef,
                    redeemFeeRatio: config.marketConfig.feeConfig.redeemFeeRatio
                })
            });

            // deploy market
            MarketInitialParams memory initialParams = MarketInitialParams({
                collateral: address(collateral),
                debtToken: IERC20Metadata(address(underlying)),
                admin: adminAddr,
                gtImplementation: address(0),
                marketConfig: marketConfig,
                loanConfig: LoanConfig({
                    oracle: oracle,
                    liquidationLtv: config.loanConfig.liquidationLtv,
                    maxLtv: config.loanConfig.maxLtv,
                    liquidatable: config.loanConfig.liquidatable
                }),
                gtInitalParams: abi.encode(type(uint256).max),
                tokenName: config.marketName,
                tokenSymbol: config.marketSymbol
            });

            TermMaxMarket market = TermMaxMarket(factory.createMarket(GT_ERC20, initialParams));
            markets[i] = market;
            router.setMarketWhitelist(address(market), true);
        }
    }

    function getGitCommitHash() public returns (bytes memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "HEAD";
        bytes memory result = vm.ffi(inputs);
        return result;
    }

    function getGitBranch() public returns (string memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "--abbrev-ref";
        inputs[3] = "HEAD";
        bytes memory result = vm.ffi(inputs);
        return string(result);
    }
}
