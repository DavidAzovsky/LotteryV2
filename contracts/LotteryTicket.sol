//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "hardhat/console.sol";

contract LotteryTicket is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    //address of the marketplace for NFTs to interface
    address marketAddress;
    mapping(address => uint) public ticketId;

    constructor(address _market) ERC721("LOTTERY", "LTY") {
        marketAddress = _market;
    }

    /**
    @notice allows minting of new token based on lotterynumber
    */
    function mintToken(address to) public returns (uint256) {
        require(marketAddress == msg.sender, "invalid caller");

        uint256 newItemId = _tokenIds.current();
        ticketId[to] = newItemId;
        _tokenIds.increment();

        _mint(to, newItemId);

        return newItemId;
    }
}
