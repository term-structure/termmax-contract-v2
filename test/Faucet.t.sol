// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {Faucet} from "../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../contracts/test/testnet/FaucetERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FaucetTest is Test {
    address deployer = vm.randomAddress();
    address user = vm.randomAddress();
    Faucet faucet;
    FaucetERC20 token;
    MockPriceFeed priceFeed;

    function setUp() public {
        vm.startPrank(deployer);
        faucet = new Faucet(deployer);
        string memory name = "TestToken";
        string memory symbol = "TT";
        uint8 decimals = 18;
        uint256 mintAmt = 1000;
        (token, priceFeed) = faucet.addToken(name, symbol, decimals, mintAmt);
        assertEq(token.owner(), address(faucet));
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.decimals(), decimals);
        assertEq(faucet.getTokenId(address(token)), 1);
        assertEq(faucet.getTokenConfig(1).mintAmt, mintAmt);
        assertEq(faucet.getTokenConfig(1).tokenAddr, address(token));
        assertEq(faucet.getTokenConfig(1).priceFeedAddr, address(priceFeed));
        assertEq(faucet.owner(), deployer);
        vm.stopPrank();
    }

    function testSetMintAmt() public {
        vm.startPrank(deployer);
        uint256 tokenId = faucet.getTokenId(address(token));
        uint256 newMintAmt = 2000;
        faucet.setMintAmt(tokenId, newMintAmt);
        assertEq(faucet.getTokenConfig(tokenId).mintAmt, newMintAmt);
        vm.stopPrank();
    }

    function testSetPriceFeed() public {
        vm.startPrank(deployer);
        uint256 tokenId = faucet.getTokenId(address(token));
        MockPriceFeed newPriceFeed = new MockPriceFeed(deployer);
        faucet.setPriceFeed(tokenId, address(newPriceFeed));
        assertEq(
            faucet.getTokenConfig(tokenId).priceFeedAddr,
            address(newPriceFeed)
        );
        vm.stopPrank();
    }

    function testSetCanOnlyMintOnce() public {
        vm.startPrank(deployer);
        assertEq(faucet.canOnlyMintOnce(), false);
        faucet.setCanOnlyMintOnce(true);
        assertEq(faucet.canOnlyMintOnce(), true);
        vm.stopPrank();
    }

    function testBatchMint() public {
        vm.startPrank(user);
        uint256 mintAmt = faucet
            .getTokenConfig(faucet.getTokenId(address(token)))
            .mintAmt;
        faucet.batchMint();
        assertEq(token.balanceOf(user), mintAmt);
        vm.stopPrank();
    }

    function testDevBatchMint() public {
        vm.startPrank(deployer);
        uint256 mintAmt = faucet
            .getTokenConfig(faucet.getTokenId(address(token)))
            .mintAmt;
        address to = vm.randomAddress();
        faucet.devBatchMint(to);
        assertEq(token.balanceOf(to), mintAmt);
        vm.stopPrank();
    }

    function testDevMint() public {
        vm.startPrank(deployer);
        uint256 mintAmt = faucet
            .getTokenConfig(faucet.getTokenId(address(token)))
            .mintAmt;
        address to = vm.randomAddress();
        faucet.devMint(to, address(token), mintAmt);
        assertEq(token.balanceOf(to), mintAmt);
        vm.stopPrank();
    }

    function testRevertAddTokenExisted() public {
        vm.startPrank(deployer);
        string memory name = "TestToken";
        string memory symbol = "TT";
        uint8 decimals = 18;
        uint256 mintAmt = 1000;
        vm.expectRevert(
            abi.encodeWithSelector(
                Faucet.TokenExisted.selector,
                name,
                symbol,
                decimals
            )
        );
        faucet.addToken(name, symbol, decimals, mintAmt);
        vm.stopPrank();
    }

    function testBatchMintTwice() public {
        vm.startPrank(user);
        uint256 mintAmt = faucet
            .getTokenConfig(faucet.getTokenId(address(token)))
            .mintAmt;
        faucet.batchMint();
        assertEq(faucet.isMinted(user), true);
        assertEq(token.balanceOf(user), mintAmt);
        faucet.batchMint();
        assertEq(token.balanceOf(user), mintAmt * 2);
        vm.stopPrank();
    }

    function testRevertBatchMintOnlyOnce() public {
        vm.startPrank(deployer);
        faucet.setCanOnlyMintOnce(true);
        vm.stopPrank();

        vm.startPrank(user);
        faucet.batchMint();
        assertEq(faucet.isMinted(user), true);
        vm.expectRevert(abi.encodeWithSelector(Faucet.OnlyMintOnce.selector));
        faucet.batchMint();
        vm.stopPrank();
    }

    function testRevertDevBatchMintNotByOwner() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        faucet.devBatchMint(user);
        vm.stopPrank();
    }

    function testRevertDevMintNotByOwner() public {
        vm.startPrank(user);
        uint256 mintAmt = faucet
            .getTokenConfig(faucet.getTokenId(address(token)))
            .mintAmt;
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        faucet.devMint(user, address(token), mintAmt);
        vm.stopPrank();
    }
}
