// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20V2} from "./IMintableERC20V2.sol";
import {MintableERC20} from "../../v1/tokens/MintableERC20.sol";

/**
 * @title TermMax ERC20 token
 * @author Term Structure Labs
 */
contract MintableERC20V2 is MintableERC20, IMintableERC20V2 {
    /**
     * @inheritdoc IMintableERC20V2
     */
    function burn(address owner, address spender, uint256 amount) external override onlyOwner {
        if (owner != spender) {
            _spendAllowance(owner, spender, amount);
        }
        _burn(owner, amount);
    }
}
