// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FaucetERC20} from "./FaucetERC20.sol";
import {MockPriceFeed} from "../MockPriceFeed.sol";

contract Faucet is Ownable {
    error OnlyMintOnce();
    error TokenExisted(string name, string symbol, uint8 decimals);

    struct TokenConfig {
        address tokenAddr;
        address priceFeedAddr;
        uint256 mintAmt;
    }
    uint256 public tokenNum;
    mapping(address => uint256) public getTokenId;
    mapping(uint256 => TokenConfig) public tokenConfigs;
    mapping(address => bool) public isMinted;
    mapping(bytes32 => uint256) public getTokenIdByKey;
    bool public canOnlyMintOnce;

    constructor(address adminAddr) Ownable(adminAddr) {}

    function getTokenConfig(
        uint256 index
    ) public view returns (TokenConfig memory) {
        return tokenConfigs[index];
    }

    function addToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 mintAmt
    ) public onlyOwner returns (FaucetERC20 token, MockPriceFeed priceFeed) {
        if (getTokenIdByKey[calcTokenKey(name, symbol, decimals)] != 0)
            revert TokenExisted(name, symbol, decimals);
        else {
            token = new FaucetERC20(address(this), name, symbol, decimals);
            priceFeed = new MockPriceFeed(owner());
            tokenNum++;
            tokenConfigs[tokenNum] = TokenConfig(
                address(token),
                address(priceFeed),
                mintAmt
            );
            getTokenId[address(token)] = tokenNum;
            getTokenIdByKey[calcTokenKey(name, symbol, decimals)] = tokenNum;
        }
    }

    function setMintAmt(uint256 index, uint256 mintAmt) public onlyOwner {
        tokenConfigs[index].mintAmt = mintAmt;
    }

    function setPriceFeed(
        uint256 index,
        address priceFeedAddr
    ) public onlyOwner {
        tokenConfigs[index].priceFeedAddr = priceFeedAddr;
    }

    function setCanOnlyMintOnce(bool _canOnlyMintOnce) public onlyOwner {
        canOnlyMintOnce = _canOnlyMintOnce;
    }

    function batchMint() public {
        if (canOnlyMintOnce && !isMinted[msg.sender]) revert OnlyMintOnce();
        if (canOnlyMintOnce) isMinted[msg.sender] = true;
        for (uint256 i = 0; i < tokenNum; i++) {
            TokenConfig memory tokenConfig = tokenConfigs[i];
            FaucetERC20(tokenConfig.tokenAddr).mint(
                msg.sender,
                tokenConfig.mintAmt
            );
        }
    }

    function devBatchMint(address to) public onlyOwner {
        for (uint256 i = 0; i < tokenNum; i++) {
            TokenConfig memory tokenConfig = tokenConfigs[i];
            FaucetERC20(tokenConfig.tokenAddr).mint(to, tokenConfig.mintAmt);
        }
    }

    function devMint(
        address to,
        address tokenAddr,
        uint256 mintAmt
    ) public onlyOwner {
        FaucetERC20(tokenAddr).mint(to, mintAmt);
    }

    function calcTokenKey(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name, symbol, decimals));
    }
}
