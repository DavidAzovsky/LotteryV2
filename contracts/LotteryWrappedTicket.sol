//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract LotteryWrappedTicket is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    //address of the marketplace for NFTs to interface
    address marketAddress;
    mapping(address => uint) public wTicketId;
    mapping(address => uint) public ticketId;

    constructor(address _marketAddress) ERC721("LOTTERY", "LTY") {
        marketAddress = _marketAddress;
    }

    /**
    @notice allows minting of new token based on lotterynumber
    */
    function mintToken(address _to, uint _ticketId) external returns (uint256) {
        require(marketAddress == msg.sender, "invalid caller");
        uint256 newItemId = _tokenIds.current();

        wTicketId[_to] = newItemId;
        ticketId[_to] = _ticketId;
        _tokenIds.increment();

        _mint(_to, newItemId);

        return newItemId;
    }

    function burnToken(address to) external {
        require(marketAddress == msg.sender, "invalid caller");
        _burn(wTicketId[to]);
    }
}
