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
    mapping(uint => uint) public pair;

    constructor(address _marketAddress) ERC721("LOTTERY", "LTY") {
        marketAddress = _marketAddress;
    }

    /**
    @notice allows minting of new token based on lotterynumber
    */
    function mintToken(address _to, uint _ticketId) external returns (uint256) {
        require(marketAddress == msg.sender, "invalid caller");

        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();
        wTicketId[_to] = newItemId;
        ticketId[_to] = _ticketId;
        pair[_ticketId] = newItemId;

        _mint(_to, newItemId);

        return newItemId;
    }

    function burnToken(address _to) external {
        require(marketAddress == msg.sender, "invalid caller");
        delete pair[ticketId[_to]];
        delete ticketId[_to];
        _burn(wTicketId[_to]);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _wTicketId
    ) external virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), _wTicketId),
            "ERC721: caller is not token owner or approved"
        );
        wTicketId[_to] = _wTicketId;
        ticketId[_to] = ticketId[_from];
        delete wTicketId[_from];
        delete ticketId[_from];
        _transfer(_from, _to, _wTicketId);
    }

    function ownerOf(
        uint256 _wTicketId
    ) external view virtual override returns (address) {
        address owner = _ownerOf(_wTicketId);
        // require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    function ticketCount() external view returns (uint256) {
        return _tokenIds.current();
    }
}
