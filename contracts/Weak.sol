// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Weak is Pausable{
    mapping(address=>uint256) public balance;

    function deposit() payable external {
        balance[msg.sender] += msg.value;
    }

    // reentry
    function withdraw() external{
        require(balance[msg.sender] > 0);
        (bool success,) = payable(msg.sender).call{value: balance[msg.sender]}("");
        require(success);
        // payable(msg.sender).transfer(balance[msg.sender]);
        balance[msg.sender] = 0;
    }

    function pause() external{
        _pause();
    }

    function unpause() external{
        _unpause();
    }

}