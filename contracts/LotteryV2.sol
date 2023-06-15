//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./LotteryV1.sol";

contract LotteryV2 is LotteryV1 {
    function getWhiteListLength() external view returns (uint256) {
        return whiteListedUsers.length;
    }
}
