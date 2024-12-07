// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITermMaxMarket} from "contracts/core/ITermMaxMarket.sol";
import {ITermMaxFactory} from "contracts/core/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {IOracle} from "contracts/core/oracle/IOracle.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

/**
 * @title TermMax Access Manager
 * @author Term Structure Labs
 */
contract AccessManager is AccessControlUpgradeable, UUPSUpgradeable {
    /// @notice Role to manage switch
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role to manage configuration items
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CURATOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @notice Set GT implementation to the factory
    function setGtImplement(
        ITermMaxFactory factory,
        string memory gtImplementName,
        address gtImplement
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        factory.setGtImplement(gtImplementName, gtImplement);
    }

    /// @notice Deploy a new market
    function createMarket(
        ITermMaxFactory factory,
        ITermMaxFactory.DeployParams calldata deployParams
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        market = factory.createMarket(deployParams);
    }

    /// @notice Deploy a new market
    function createMarketAndWhitelist(
        ITermMaxRouter router,
        ITermMaxFactory factory,
        ITermMaxFactory.DeployParams calldata deployParams
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        market = factory.createMarket(deployParams);
        router.setMarketWhitelist(market, true);
    }

    /// @notice Transfer ownable contract's ownership
    function transferOwnership(
        address entity,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IOwnable(entity).transferOwnership(to);
    }

    /// @notice Upgrade the target contract using UUPS
    function upgradeSubContract(
        UUPSUpgradeable proxy,
        address newImplementation,
        bytes memory data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proxy.upgradeToAndCall(newImplementation, data);
    }

        /// @notice Set the market whitelist for router
    function setMarketWhitelist(
        ITermMaxRouter router,
        address market,
        bool isWhitelist
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        router.setMarketWhitelist(market, isWhitelist);
    }

    /// @notice Set the adapter whitelist for router
    function setAdapterWhitelist(
        ITermMaxRouter router,
        address adapter,
        bool isWhitelist
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        router.setAdapterWhitelist(adapter, isWhitelist);
    }

    /// @notice Set the oracle
    function setOracle(IOracle aggregator, address asset, IOracle.Oracle memory oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aggregator.setOracle(asset, oracle);
    }

    /// @notice Withdraw excess FT and XT tokens from the market
    function withdrawExcessFtXt(
        ITermMaxMarket market,
        address to,
        uint128 ftAmt,
        uint128 xtAmt
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        market.withdrawExcessFtXt(to, ftAmt, xtAmt);
    }

    /// @notice Set the fee rate of the market
    function setMarketFeeRate(
        ITermMaxMarket market,
        uint32 lendFeeRatio,
        uint32 minNLendFeeR,
        uint32 borrowFeeRatio,
        uint32 minNBorrowFeeR,
        uint32 redeemFeeRatio,
        uint32 issueFtfeeRatio,
        uint32 lockingPercentage,
        uint32 protocolFeeRatio
    ) external onlyRole(CURATOR_ROLE) {
        market.setFeeRate(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtfeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
    }

    /// @notice Set the treasurer's address
    function setMarketTreasurer(
        ITermMaxMarket market,
        address treasurer
    ) external onlyRole(CURATOR_ROLE) {
        market.setTreasurer(treasurer);
    }

    /// @notice Set the value of lsf
    function setMarketLsf(
        ITermMaxMarket market,
        uint32 lsf
    ) external onlyRole(CURATOR_ROLE) {
        market.setLsf(lsf);
    }
    
    /// @notice Set the provider's white list
    function setProviderWhitelist(ITermMaxMarket market, address provider, bool isWhiteList) external onlyRole(CURATOR_ROLE) {
        market.setProviderWhitelist(provider, isWhiteList);
    }

    /// @notice Set the configuration of Gearing Token
    function updateGtConfig(ITermMaxMarket market, bytes memory configData) external onlyRole(CURATOR_ROLE){
        market.updateGtConfig(configData);
    }

    /// @notice Set the switch for this market
    function setSwitchOfMarket(
        ITermMaxMarket market,
        bool state
    ) external onlyRole(PAUSER_ROLE) {
        if (state) {
            market.unpause();
        } else {
            market.pause();
        }
    }

    /// @notice Set the switch for Router
    function setSwitchOfRouter(
        ITermMaxRouter router,
        bool state
    ) external onlyRole(PAUSER_ROLE) {
        router.togglePause(state);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
