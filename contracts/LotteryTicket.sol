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
    function mintToken(address _to) external returns (uint256) {
        require(marketAddress == msg.sender, "invalid caller");

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        ticketId[_to] = newItemId;
        _mint(_to, newItemId);

        return newItemId;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), _tokenId),
            "ERC721: caller is not token owner or approved"
        );
        ticketId[_to] = _tokenId;
        delete ticketId[_from];
        _transfer(_from, _to, _tokenId);
    }

    function ownerOf(
        uint256 _tokenId
    ) external view virtual override returns (address) {
        address owner = _ownerOf(_tokenId);
        // require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    function ticketCount() external view returns (uint256) {
        return _tokenIds.current();
    }
}
