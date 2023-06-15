// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract VRFConsumerBaseV2Upgradeable is Initializable {
    error OnlyCoordinatorCanFulfill(address have, address want);
    address private vrfCoordinator;

    function __VRFConsumerBaseV2Upgradeable_init(
        address _vrfCoordinator
    ) public {
        vrfCoordinator = _vrfCoordinator;
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal virtual;

    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(msg.sender, vrfCoordinator);
        }
        fulfillRandomWords(requestId, randomWords);
    }
}
