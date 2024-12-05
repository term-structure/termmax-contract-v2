// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken, AggregatorV3Interface} from "../../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "../../contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "../../contracts/test/testnet/Faucet.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {FaucetERC20} from "../../contracts/test/testnet/FaucetERC20.sol";

contract DeployBase is Script {
    function deployCore(
        address adminAddr
    )
        public
        returns (
            Faucet faucet,
            TermMaxFactory factory,
            TermMaxRouter router,
            SwapAdapter swapAdapter
        )
    {
        // deploy factory
        factory = new TermMaxFactory(adminAddr);
        TermMaxMarket marketImpl = new TermMaxMarket();
        factory.initMarketImplement(address(marketImpl));

        // deploy router
        address routerImpl = address(new TermMaxRouter());
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, adminAddr);
        address proxy = address(new ERC1967Proxy(routerImpl, data));
        router = TermMaxRouter(proxy);
        router.togglePause(false);

        // deploy swap adapter
        swapAdapter = new SwapAdapter(adminAddr);
        router.setAdapterWhitelist(address(swapAdapter), true);

        // deploy faucet
        faucet = new Faucet(adminAddr);
    }

    function deployMarkets(
        address factoryAddr,
        address routerAddr,
        address faucetAddr,
        string memory deployDataPath,
        address adminAddr,
        address priceFeedOperatorAddr,
        uint64 openTimeDelay
    ) public returns (TermMaxMarket[] memory markets) {
        TermMaxFactory factory = TermMaxFactory(factoryAddr);
        TermMaxRouter router = TermMaxRouter(routerAddr);
        Faucet faucet = Faucet(faucetAddr);

        string memory deployData = vm.readFile(deployDataPath);

        JsonLoader.Config[] memory configs = JsonLoader.getConfigsFromJson(
            deployData
        );

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
                    config.collateralConfig.decimals,
                    config.collateralConfig.mintAmt
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
                collateral = FaucetERC20(
                    faucet.getTokenConfig(tokenId).tokenAddr
                );
                collateralPriceFeed = MockPriceFeed(
                    faucet.getTokenConfig(tokenId).priceFeedAddr
                );
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
                    config.underlyingConfig.decimals,
                    config.underlyingConfig.mintAmt
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
                underlying = FaucetERC20(
                    faucet.getTokenConfig(tokenId).tokenAddr
                );
                underlyingPriceFeed = MockPriceFeed(
                    faucet.getTokenConfig(tokenId).priceFeedAddr
                );
            }

            MarketConfig memory marketConfig = MarketConfig({
                treasurer: config.marketConfig.treasurer,
                maturity: config.marketConfig.maturity,
                openTime: uint64(vm.getBlockTimestamp() + openTimeDelay),
                apr: config.marketConfig.apr,
                lsf: config.marketConfig.lsf,
                lendFeeRatio: config.marketConfig.lendFeeRatio,
                minNLendFeeR: config.marketConfig.minNLendFeeR,
                borrowFeeRatio: config.marketConfig.borrowFeeRatio,
                minNBorrowFeeR: config.marketConfig.minNBorrowFeeR,
                redeemFeeRatio: config.marketConfig.redeemFeeRatio,
                issueFtFeeRatio: config.marketConfig.issueFtFeeRatio,
                lockingPercentage: config.marketConfig.lockingPercentage,
                initialLtv: config.marketConfig.initialLtv,
                protocolFeeRatio: config.marketConfig.protocolFeeRatio,
                rewardIsDistributed: false
            });

            // deploy market
            ITermMaxFactory.DeployParams memory params = ITermMaxFactory
                .DeployParams({
                    gtKey: keccak256(
                        bytes(config.collateralConfig.gtKeyIdentifier)
                    ),
                    admin: adminAddr,
                    collateral: address(collateral),
                    underlying: IERC20Metadata(address(underlying)),
                    underlyingOracle: AggregatorV3Interface(
                        address(underlyingPriceFeed)
                    ),
                    liquidationLtv: config.marketConfig.liquidationLtv,
                    maxLtv: config.marketConfig.maxLtv,
                    liquidatable: config.marketConfig.liquidatable,
                    marketConfig: marketConfig,
                    gtInitalParams: abi.encode(address(collateralPriceFeed))
                });
            TermMaxMarket market = TermMaxMarket(factory.createMarket(params));
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
