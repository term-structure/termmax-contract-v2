// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

struct WhitelistConfig {
    bool fromWhitelisted;
    bool toWhitelisted;
}

contract PreTMX is ERC20, Ownable2Step {
    bool public transferEnabled;

    mapping(address => WhitelistConfig) public whitelistConfig;

    error TransferNotWhitelisted(address from, address to);

    event TransferEnabled(bool enabled);
    event TransferWhitelisted(address wallet, bool isFromWhitelisted, bool isToWhitelisted);

    constructor(address admin) ERC20("Pre TermMax Token", "pTMX") Ownable(admin) {
        _mint(admin, 1e9 ether);
        _setTransferEnabled(false);
        _setTransferWhitelisted(admin, true, true);
    }

    function enableTransfer() external onlyOwner {
        _setTransferEnabled(true);
    }

    function disableTransfer() external onlyOwner {
        _setTransferEnabled(false);
    }

    function whitelistTransfer(address wallet, bool isFromWhitelisted, bool isToWhitelisted) external onlyOwner {
        _setTransferWhitelisted(wallet, isFromWhitelisted, isToWhitelisted);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _beforeTokenTransfer(msg.sender, to);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _beforeTokenTransfer(from, to);
        return super.transferFrom(from, to, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    function _beforeTokenTransfer(address from, address to) internal view {
        if (!transferEnabled) {
            if (!whitelistConfig[from].fromWhitelisted && !whitelistConfig[to].toWhitelisted) {
                revert TransferNotWhitelisted(from, to);
            }
        }
    }

    function _setTransferEnabled(bool enabled) internal {
        transferEnabled = enabled;
        emit TransferEnabled(enabled);
    }

    function _setTransferWhitelisted(address wallet, bool isFromWhitelisted, bool isToWhitelisted) internal {
        whitelistConfig[wallet] = WhitelistConfig({fromWhitelisted: isFromWhitelisted, toWhitelisted: isToWhitelisted});
        emit TransferWhitelisted(wallet, isFromWhitelisted, isToWhitelisted);
    }
}
