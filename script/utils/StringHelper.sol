// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {VmSafe} from "forge-std/Vm.sol";

library StringHelper {
    function toUpper(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bUpper = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            // Convert hyphen to underscore
            if (bStr[i] == 0x2D) {
                bUpper[i] = 0x5F; // '_'
                continue;
            }
            // Convert lowercase to uppercase
            if ((uint8(bStr[i]) >= 97) && (uint8(bStr[i]) <= 122)) {
                bUpper[i] = bytes1(uint8(bStr[i]) - 32);
            } else {
                bUpper[i] = bStr[i];
            }
        }
        return string(bUpper);
    }

    // Format options:
    // 'YYYYMMDD' = YYYYMMDD (e.g., 20250626)
    // 'DDMMMYYYY' = DDMMMYYYY (e.g., 26JUN2025)
    function convertTimestampToDateString(uint256 timestamp, string memory format)
        internal
        pure
        returns (string memory)
    {
        // Define arrays for date conversion
        string[12] memory months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        uint8[12] memory daysPerMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        uint8[12] memory daysPerMonthLeap = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

        // Convert timestamp to days since epoch
        uint256 secondsPerDay = 24 * 60 * 60;
        uint256 daysSinceEpoch = timestamp / secondsPerDay;

        // Start from 1970-01-01
        uint256 year = 1970;
        uint256 month = 0; // 0-indexed month
        uint256 day = 0; // 0-indexed day

        // Count years
        while (true) {
            bool leapYearCheck = (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0));
            uint256 daysInYear = leapYearCheck ? 366 : 365;

            if (daysSinceEpoch < daysInYear) {
                break;
            }

            daysSinceEpoch -= daysInYear;
            year++;
        }

        // Count months
        bool isLeapYear = (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0));

        // Process each month
        for (uint256 i = 0; i < 12; i++) {
            uint8 daysInCurrentMonth = isLeapYear ? daysPerMonthLeap[i] : daysPerMonth[i];
            if (daysSinceEpoch < daysInCurrentMonth) {
                month = i;
                break;
            }
            daysSinceEpoch -= daysInCurrentMonth;
        }

        // Remaining days (plus 1 because days are 1-indexed)
        day = daysSinceEpoch + 1;

        VmSafe vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

        if (keccak256(abi.encodePacked(format)) == keccak256(abi.encodePacked("YYYYMMDD"))) {
            // Format YYYYMMDD: (e.g., 20250626)
            string memory monthStr;
            if (month + 1 < 10) {
                monthStr = string.concat("0", vm.toString(month + 1));
            } else {
                monthStr = vm.toString(month + 1);
            }

            string memory dayStr;
            if (day < 10) {
                dayStr = string.concat("0", vm.toString(day));
            } else {
                dayStr = vm.toString(day);
            }

            return string.concat(vm.toString(year), monthStr, dayStr);
        } else {
            // Format DDMMMYYYY: (e.g., 26JUN2025)
            string memory dayStr;
            if (day < 10) {
                dayStr = string.concat("0", vm.toString(day));
            } else {
                dayStr = vm.toString(day);
            }

            return string.concat(dayStr, months[month], vm.toString(year));
        }
    }
}
