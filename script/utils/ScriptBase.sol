// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StringHelper} from "../utils/StringHelper.sol";

/**
 * @title ScriptBase
 * @notice Base contract for contract call scripts with JSON output functionality
 */
contract ScriptBase is Script {
    // Helper function to generate date suffix for JSON files
    function getDateSuffix() internal view returns (string memory) {
        return StringHelper.convertTimestampToDateString(block.timestamp, "YYYY-MM-DD");
    }

    // Helper function to create script execution file path with date suffix
    function getScriptExecutionFilePath(string memory network, string memory scriptName)
        internal
        view
        returns (string memory)
    {
        string memory dateSuffix = getDateSuffix();
        string memory executionsDir = string.concat(vm.projectRoot(), "/executions/", network);
        return string.concat(executionsDir, "/", network, "-", scriptName, "-", dateSuffix, ".json");
    }

    // Helper function to write script execution results to JSON
    function writeScriptExecutionResults(string memory network, string memory scriptName, string memory executionData)
        internal
    {
        // Create executions directory if it doesn't exist
        string memory executionsDir = string.concat(vm.projectRoot(), "/executions/", network);
        if (!vm.exists(executionsDir)) {
            vm.createDir(executionsDir, true);
        }

        // Write the JSON file with date suffix
        string memory filePath = getScriptExecutionFilePath(network, scriptName);
        vm.writeFile(filePath, executionData);
        console.log("Script execution information written to:", filePath);
    }

    // Helper function to get git commit hash
    function getGitCommitHash() internal returns (bytes memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "HEAD";
        bytes memory result = vm.ffi(inputs);
        return result;
    }

    // Helper function to get git branch
    function getGitBranch() internal returns (string memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "--abbrev-ref";
        inputs[3] = "HEAD";
        bytes memory result = vm.ffi(inputs);
        return string(result);
    }

    // Helper function to convert string to uppercase
    function toUpper(string memory str) internal pure returns (string memory) {
        return StringHelper.toUpper(str);
    }

    // Helper function to create base execution JSON structure
    function createBaseExecutionJson(
        string memory network,
        string memory scriptName,
        uint256 executionBlock,
        uint256 executionTimestamp
    ) internal returns (string memory) {
        return string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                network,
                '",\n',
                '  "scriptName": "',
                scriptName,
                '",\n',
                '  "executedAt": "',
                vm.toString(executionTimestamp),
                '",\n',
                '  "gitBranch": "',
                getGitBranch(),
                '",\n',
                '  "gitCommitHash": "0x',
                vm.toString(getGitCommitHash()),
                '",\n',
                '  "blockInfo": {\n',
                '    "number": "',
                vm.toString(executionBlock),
                '",\n',
                '    "timestamp": "',
                vm.toString(executionTimestamp),
                '"\n',
                "  }"
            )
        );
    }
}
