// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract PreTMX is ERC20, Ownable2Step {
    struct WhitelistInfo {
        bool isTransferFromWhitelisted;
        bool isTransferToWhitelisted;
    }

    bool public transferRestricted;

    mapping(address => WhitelistInfo) public whitelistMapping;

    error TransferNotWhitelisted(address from, address to);

    event TransferRestricted(bool restricted);
    event TransferWhitelisted(address indexed user, bool isTransferFromWhitelisted, bool isTransferToWhitelisted);

    constructor(address admin) ERC20("Pre TermMax Token", "pTMX") Ownable(admin) {
        _mint(admin, 1e9 ether);
        _setTransferRestricted(true);
        _setTransferWhitelisted(admin, true, true);
    }

    function enableTransfer() external onlyOwner {
        _setTransferRestricted(false);
    }

    function disableTransfer() external onlyOwner {
        _setTransferRestricted(true);
    }

    function whitelistTransfer(address user, bool isTransferFromWhitelisted, bool isTransferToWhitelisted)
        external
        onlyOwner
    {
        _setTransferWhitelisted(user, isTransferFromWhitelisted, isTransferToWhitelisted);
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
        if (
            transferRestricted && !whitelistMapping[from].isTransferFromWhitelisted
                && !whitelistMapping[to].isTransferToWhitelisted
        ) {
            revert TransferNotWhitelisted(from, to);
        }
    }

    function _setTransferRestricted(bool restricted) internal {
        transferRestricted = restricted;
        emit TransferRestricted(restricted);
    }

    function _setTransferWhitelisted(address user, bool isTransferFromWhitelisted, bool isTransferToWhitelisted)
        internal
    {
        whitelistMapping[user].isTransferFromWhitelisted = isTransferFromWhitelisted;
        whitelistMapping[user].isTransferToWhitelisted = isTransferToWhitelisted;
        emit TransferWhitelisted(user, isTransferFromWhitelisted, isTransferToWhitelisted);
    }
}
