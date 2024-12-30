// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITermMaxMarket} from "contracts/core/ITermMaxMarket.sol";
import {ITermMaxFactory} from "contracts/core/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {IOracle} from "contracts/core/oracle/IOracle.sol";
import {MarketConfig} from "contracts/core/storage/TermMaxStorage.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

/**
 * @title TermMax Access Manager
 * @author Term Structure Labs
 */
contract AccessManager is AccessControlUpgradeable, UUPSUpgradeable {
    /// @notice Error when msg.sender is not curator
    error MsgSenderIsNotCurator(ITermMaxMarket market);

    /// @notice Error when revoking default admin role
    error CannotRevokeDefaultAdminRole();

    /// @notice Emit when updating market curator
    /// @param market The market's address
    /// @param curator The curator's address
    event UpdateMarketCurator(ITermMaxMarket market, address curator);

    /// @notice Role to manage switch
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    /// @notice Market curators
    mapping(ITermMaxMarket => address) public marketCurators;

    modifier onlyCurator(ITermMaxMarket market) {
        if (
            hasRole(CURATOR_ROLE, msg.sender) ||
            marketCurators[market] == msg.sender
        ) {
            _;
        } else {
            revert MsgSenderIsNotCurator(market);
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
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
    function setOracle(
        IOracle aggregator,
        address asset,
        IOracle.Oracle memory oracle
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aggregator.setOracle(asset, oracle);
    }

    /// @notice Remove the oracle
    function removeOracle(
        IOracle aggregator,
        address asset
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aggregator.removeOracle(asset);
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

    /// @notice Set the market curator
    function setMarketCurator(
        ITermMaxMarket market,
        address curator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        marketCurators[market] = curator;
        emit UpdateMarketCurator(market, curator);
    }

    /// @notice Update the market configuration
    function updateMarketConfig(
        ITermMaxMarket market,
        MarketConfig calldata newConfig
    ) external onlyCurator(market) {
        market.updateMarketConfig(newConfig);
    }

    /// @notice Set the provider's white list
    function setProviderWhitelist(
        ITermMaxMarket market,
        address provider,
        bool isWhiteList
    ) external onlyCurator(market) {
        market.setProviderWhitelist(provider, isWhiteList);
    }

    /// @notice Set the configuration of Gearing Token
    function updateGtConfig(
        ITermMaxMarket market,
        bytes memory configData
    ) external onlyCurator(market) {
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

    /// @notice Revoke role
    /// @dev Can't revoke your own role
    function revokeRole(
        bytes32 role,
        address account
    ) public override onlyRole(getRoleAdmin(role)) {
        if (msg.sender == account) {
            revert AccessControlBadConfirmation();
        }

        _revokeRole(role, account);
    }

    /// @notice Revoke role
    /// @dev Can't revoke default admin role
    function renounceRole(
        bytes32 role,
        address callerConfirmation
    ) public override {
        if (role == DEFAULT_ADMIN_ROLE) {
            revert CannotRevokeDefaultAdminRole();
        }
        _revokeRole(role, callerConfirmation);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
