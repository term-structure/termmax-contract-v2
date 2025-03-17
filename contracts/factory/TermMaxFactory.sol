// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {TermMaxMarket} from "../TermMaxMarket.sol";
import {GearingTokenWithERC20} from "../tokens/GearingTokenWithERC20.sol";
import {MarketInitialParams} from "../storage/TermMaxStorage.sol";
import {FactoryErrors} from "../errors/FactoryErrors.sol";
import {FactoryEvents} from "../events/FactoryEvents.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxFactory} from "./ITermMaxFactory.sol";

/**
 * @title The TermMax factory
 * @author Term Structure Labs
 */
contract TermMaxFactory is Ownable2Step, FactoryErrors, FactoryEvents, ITermMaxFactory {
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    /// @notice The implementation of TermMax Market contract
    address public immutable TERMMAX_MARKET_IMPLEMENTATION;

    /// @notice The implementations of TermMax Gearing Token contract
    /// @dev Based on the abstract GearingToken contract,
    ///      different GearingTokens can be adapted to various collaterals,
    ///      such as ERC20 tokens and ERC721 tokens.
    mapping(bytes32 => address) public gtImplements;

    constructor(address admin, address TERMMAX_MARKET_IMPLEMENTATION_) Ownable(admin) {
        if (TERMMAX_MARKET_IMPLEMENTATION_ == address(0)) {
            revert InvalidImplementation();
        }
        TERMMAX_MARKET_IMPLEMENTATION = TERMMAX_MARKET_IMPLEMENTATION_;

        gtImplements[GT_ERC20] = address(new GearingTokenWithERC20());
    }

    function setGtImplement(string memory gtImplementName, address gtImplement) external onlyOwner {
        bytes32 key = keccak256(abi.encodePacked(gtImplementName));
        gtImplements[key] = gtImplement;
        emit SetGtImplement(key, gtImplement);
    }

    function predictMarketAddress(
        address deployer,
        address collateral,
        address debtToken,
        uint64 maturity,
        uint256 salt
    ) external view returns (address market) {
        return Clones.predictDeterministicAddress(
            TERMMAX_MARKET_IMPLEMENTATION, keccak256(abi.encode(deployer, collateral, debtToken, maturity, salt))
        );
    }

    function createMarket(bytes32 gtKey, MarketInitialParams memory params, uint256 salt)
        external
        onlyOwner
        returns (address market)
    {
        params.gtImplementation = gtImplements[gtKey];
        if (params.gtImplementation == address(0)) {
            revert CantNotFindGtImplementation();
        }
        market = Clones.cloneDeterministic(
            TERMMAX_MARKET_IMPLEMENTATION,
            keccak256(abi.encode(msg.sender, params.collateral, params.debtToken, params.marketConfig.maturity, salt))
        );
        ITermMaxMarket(market).initialize(params);

        emit CreateMarket(market, params.collateral, params.debtToken);
    }
}
