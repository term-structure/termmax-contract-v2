// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITermMaxMarket} from "contracts/core/ITermMaxMarket.sol";
import {ITermMaxFactory} from "contracts/core/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

/**
 * @title TermMax Access Manager
 * @author Term Structure Labs
 */
contract AccessManager is AccessControlUpgradeable, UUPSUpgradeable {
    address public immutable zkTrueUp;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CURATOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

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

    function transferOwnership(
        address entity,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IOwnable(entity).transferOwnership(to);
    }

    function upgradeSubContract(
        UUPSUpgradeable proxy,
        address newImplementation,
        bytes memory data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proxy.upgradeToAndCall(newImplementation, data);
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

    function setSwitchOfMintingGt(
        ITermMaxMarket market,
        bool state
    ) external onlyRole(CURATOR_ROLE) {
        market.updateMintingGtSwitch(state);
    }

    function setMarketWhitelist(
        ITermMaxRouter router,
        address market,
        bool isWhitelist
    ) external onlyRole(CURATOR_ROLE) {
        router.setMarketWhitelist(market, isWhitelist);
    }

    function setAdapterWhitelist(
        ITermMaxRouter router,
        address adapter,
        bool isWhitelist
    ) external onlyRole(CURATOR_ROLE) {
        router.setAdapterWhitelist(adapter, isWhitelist);
    }

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

    function setSwitchOfGt(
        ITermMaxMarket market,
        bool state
    ) external onlyRole(PAUSER_ROLE) {
        if (state) {
            market.unpauseGt();
        } else {
            market.pauseGt();
        }
    }

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
