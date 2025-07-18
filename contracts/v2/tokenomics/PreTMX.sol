// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract PreTMX is ERC20, Ownable2Step {
    bool public transferRestricted;

    mapping(address => bool) public isTransferredFromWhitelisted;

    error TransferFromNotWhitelisted(address from);

    event TransferRestricted(bool restricted);
    event TransferFromWhitelisted(address from, bool isWhitelisted);

    constructor(address admin) ERC20("Pre TermMax Token", "pTMX") Ownable(admin) {
        _mint(admin, 1e9 ether);
        _setTransferRestricted(true);
        _setTransferFromWhitelisted(admin, true);
    }

    function enableTransfer() external onlyOwner {
        _setTransferRestricted(false);
    }

    function disableTransfer() external onlyOwner {
        _setTransferRestricted(true);
    }

    function whitelistTransferFrom(address from, bool isWhitelisted) external onlyOwner {
        _setTransferFromWhitelisted(from, isWhitelisted);
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

    function _beforeTokenTransfer(address from, address) internal view {
        if (transferRestricted && !isTransferredFromWhitelisted[from]) {
            revert TransferFromNotWhitelisted(from);
        }
    }

    function _setTransferRestricted(bool restricted) internal {
        transferRestricted = restricted;
        emit TransferRestricted(restricted);
    }

    function _setTransferFromWhitelisted(address from, bool isWhitelisted) internal {
        isTransferredFromWhitelisted[from] = isWhitelisted;
        emit TransferFromWhitelisted(from, isWhitelisted);
    }
}
