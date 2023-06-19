//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2Upgradeable.sol";
import "./LotteryTicket.sol";
import "./LotteryWrappedTicket.sol";

contract LotteryV1 is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    VRFConsumerBaseV2Upgradeable
{
    LotteryTicket ticket;
    LotteryWrappedTicket wTicket;

    bytes32 internal keyHash;
    uint256 internal feeChainlink;
    uint64 subscriptionId;
    VRFCoordinatorV2Interface COORDINATOR;
    uint256[] public requestIDs;

    bytes32 public merkleRoot;

    uint256 public feeProtocol;
    uint256 public feeRent;
    uint256 public rentAmount;
    uint256 public currentWinnerCount;

    uint256 public startTime;

    //price of Lottery Ticket
    mapping(uint => uint) public ticketsPrice;
    mapping(address => uint256) public balanceDepositors;

    //LotteryInfo
    struct LotteryInfo {
        uint256 depositCount;
        uint256 totalValue;
        uint256 winnerCount;
        mapping(address => bool) whiteListed;
        mapping(uint256 => address) depositors;
        mapping(address => uint256) amount;
        mapping(uint256 => address) winners;
        uint256 totalAmount;
    }

    mapping(uint256 => LotteryInfo) public lotteryInfo;
    uint256 public lotteryId;

    uint256 constant DEPOSIT_PERIOD = 86400 * 7;
    uint256 constant BREAK_PERIOD = 86400 * 7;

    enum LOTTERY_STATE {
        OPEN,
        BREAK,
        CLOSE,
        CALCULATING_WINNER
    }
    LOTTERY_STATE public lotteryState;

    event RequestRandomNumber(bytes32 id);
    event FullFillRandomNumber(uint256 random);
    event UpdateWinners(uint256 lotteryID, address[] winners);

    function initialize(
        uint64 _subscriptionId,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _fee
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __VRFConsumerBaseV2Upgradeable_init(_vrfCoordinator);
        keyHash = _keyHash;
        feeChainlink = _fee;

        subscriptionId = _subscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        lotteryState = LOTTERY_STATE.CLOSE;
    }

    function enter(bytes32[] calldata data) external payable nonReentrant {
        require(lotteryState == LOTTERY_STATE.OPEN, "Lottery not opened");

        // verify if whitelisted user enters with msg.data
        LotteryInfo storage curLottery = lotteryInfo[lotteryId];
        if (data.length > 0) {
            bytes32[] memory proof = data;
            if (verifiedWhiteListedUser(proof, msg.sender))
                curLottery.amount[msg.sender] = 0.5 ether;
        }
        // If msg.sender is nft Owner, borrower, or new depositor
        else if (ticket.ticketId(msg.sender) != 0) {
            uint ticketId = ticket.ticketId(msg.sender);

            require(
                wTicket.pair(ticketId) == 0,
                "Cannot enter, rented to other"
            );
            curLottery.amount[msg.sender] = msg.value + ticketsPrice[ticketId];
        } else if (wTicket.wTicketId(msg.sender) != 0) {
            uint ticketId = wTicket.ticketId(msg.sender);
            curLottery.amount[msg.sender] = msg.value + ticketsPrice[ticketId];
        } else {
            require(msg.value > 0, "Invalid new depositor amount");

            curLottery.amount[msg.sender] = msg.value;

            uint ticketId = ticket.mintToken(msg.sender);
            ticketsPrice[ticketId] = msg.value;
        }

        curLottery.depositors[curLottery.depositCount++] = msg.sender;

        curLottery.totalAmount += curLottery.amount[msg.sender];
        curLottery.totalValue += msg.value;
    }

    function rentTicket(uint256 ticketId) external payable nonReentrant {
        require(lotteryState == LOTTERY_STATE.OPEN, "deposit period finished");
        require(ticket.ownerOf(ticketId) != msg.sender, "ticketId is it's own");
        require(wTicket.pair(ticketId) == 0, "rent already");
        require(
            ticketId <= ticket.ticketCount() && ticketId > 0,
            "invalid ticketID"
        );

        LotteryInfo storage curLottery = lotteryInfo[lotteryId];
        for (uint i = 0; i < curLottery.depositCount; i++) {
            if (curLottery.depositors[i] == ticket.ownerOf(ticketId))
                revert("deposited already");
        }

        require(msg.value >= rentAmount, "invalid input amount");
        //mint wrapped ticket
        wTicket.mintToken(msg.sender, ticketId);

        payable(ticket.ownerOf(ticketId)).transfer(rentAmount);
    }

    //Claim rewards for Winner
    function claim() external nonReentrant {
        require(
            ticket.ticketId(msg.sender) != 0 ||
                wTicket.wTicketId(msg.sender) != 0,
            "borrower cannot claim if not break period"
        );
        if (wTicket.wTicketId(msg.sender) != 0) {
            // if borrower is not winner, then revert
            require(isWinner(msg.sender), "borrower but not winner");

            uint ticketId = wTicket.ticketId(msg.sender);

            // send feeRent percent of reward to nft owner and borrower gets rest amount
            uint256 reward = (lotteryInfo[lotteryId].totalValue *
                (100 - feeProtocol)) /
                currentWinnerCount /
                100;

            // add reward to nft owner's reward balance
            balanceDepositors[ticket.ownerOf(ticketId)] +=
                (reward * feeRent) /
                100;
            // burn wrapped nft
            wTicket.burnToken(msg.sender);
            //transfer reward to borrower
            payable(msg.sender).transfer((reward * (100 - feeRent)) / 100);
        } else {
            // if nft owner's borrower is winner
            uint256 ticketId = ticket.ticketId(msg.sender);
            address borrower = wTicket.ownerOf(wTicket.pair(ticketId));
            if (isWinner(borrower) && lotteryState == LOTTERY_STATE.BREAK)
                revert("borrower not claimed, he is winner");

            if (borrower != address(0)) wTicket.burnToken(borrower);
            uint reward = balanceDepositors[msg.sender];
            balanceDepositors[msg.sender] = 0;
            payable(msg.sender).transfer(reward);
        }
    }

    function startLottery() external onlyOwner {
        require(lotteryState == LOTTERY_STATE.CLOSE, "Cannot start lottery");

        // Update lotteryInfo
        lotteryState = LOTTERY_STATE.OPEN;
        lotteryId++;
        startTime = block.timestamp;
    }

    function breakLottery() external onlyOwner {
        require(
            lotteryState == LOTTERY_STATE.OPEN &&
                (block.timestamp >= startTime + DEPOSIT_PERIOD) &&
                block.timestamp <= (startTime + DEPOSIT_PERIOD + BREAK_PERIOD),
            "Cannot break lottery"
        );

        lotteryState = LOTTERY_STATE.CALCULATING_WINNER;
        requestRandomNumbers();
    }

    function endLottery() external onlyOwner {
        require(
            lotteryState == LOTTERY_STATE.BREAK &&
                block.timestamp > (startTime + DEPOSIT_PERIOD + BREAK_PERIOD),
            "Cannot end lottery"
        );

        lotteryState = LOTTERY_STATE.CLOSE;
        //burn Wrapped nft, so borrowers cannot win prize anymore and nft owner can claim all
        for (uint i = 1; i <= ticket.ticketCount(); i++) {
            address borrower = wTicket.ownerOf(wTicket.pair(i));
            if (borrower != address(0)) {
                // if borrower is winner, nft owner claim all reward
                if (isWinner(borrower)) {
                    uint256 reward = (lotteryInfo[lotteryId].totalValue *
                        (100 - feeProtocol)) /
                        currentWinnerCount /
                        100;
                    balanceDepositors[ticket.ownerOf(i)] += reward;
                }

                //burn wrapped nft
                wTicket.burnToken(borrower);
            }
        }
    }

    function setFeeProtocol(uint256 amount) external onlyOwner {
        feeProtocol = amount;
    }

    function setFeeRent(uint256 amount) external onlyOwner {
        feeRent = amount;
    }

    function setRentAmount(uint256 amount) external onlyOwner {
        rentAmount = amount;
    }

    function setWinnerNumbers(uint256 amount) external onlyOwner {
        currentWinnerCount = amount;
    }

    function setTickets(address _ticket, address _wTicket) external onlyOwner {
        ticket = LotteryTicket(_ticket);
        wTicket = LotteryWrappedTicket(_wTicket);
    }

    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
    }

    function getWinnerAddress(
        uint _lotteryId
    ) external view returns (address[] memory) {
        require(
            (_lotteryId < lotteryId) ||
                (_lotteryId == lotteryId &&
                    lotteryState == LOTTERY_STATE.BREAK),
            "invalid lottery or cannot get winners after break period"
        );
        address[] memory winnerAddress;
        winnerAddress = new address[](lotteryInfo[_lotteryId].winnerCount);
        for (uint i = 0; i < lotteryInfo[_lotteryId].winnerCount; i++)
            winnerAddress[i] = lotteryInfo[lotteryId].winners[i];
        return winnerAddress;
    }

    function verifiedWhiteListedUser(
        bytes32[] memory proof,
        address user
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProofUpgradeable.verify(proof, merkleRoot, leaf);
    }

    function requestRandomNumbers() internal {
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            3,
            200000,
            uint32(currentWinnerCount)
        );
        requestIDs.push(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        LotteryInfo storage currentLottery = lotteryInfo[lotteryId];
        address[] memory depositors = new address[](
            currentLottery.depositCount
        );

        uint256 totalWeight = currentLottery.totalAmount;
        for (uint i = 0; i < depositors.length; i++)
            depositors[i] = currentLottery.depositors[i];

        for (uint i = 0; i < currentWinnerCount; i++) {
            uint256 rand = uint256(
                keccak256(abi.encodePacked(randomWords[i]))
            ) % totalWeight;

            uint256 weightSum = 0;
            uint j;
            for (j = 0; j < depositors.length; j++) {
                weightSum += currentLottery.amount[depositors[j]];
                if (rand < weightSum) {
                    currentLottery.winners[
                        currentLottery.winnerCount++
                    ] = depositors[j];
                    break;
                }
            }

            //IF not borrower, add reward balance to balanceDepositors
            if (wTicket.wTicketId(depositors[j]) == 0)
                balanceDepositors[depositors[j]] +=
                    (currentLottery.totalValue * (100 - feeProtocol)) /
                    currentWinnerCount /
                    100;

            totalWeight -= currentLottery.amount[depositors[j]];
            delete depositors[j];
        }
        lotteryState = LOTTERY_STATE.BREAK;

        // emit UpdateWinners event
        address[] memory winnerAddress = new address[](currentWinnerCount);
        for (uint i = 0; i < currentWinnerCount; i++)
            winnerAddress[i] = currentLottery.winners[i];

        emit UpdateWinners(lotteryId, winnerAddress);
    }

    //Todo change isWinner returns to bool
    function isWinner(address user) internal view returns (bool) {
        uint256 i;
        for (i = 0; i < currentWinnerCount; i++)
            if (lotteryInfo[lotteryId].winners[i] == user) break;

        if (i < currentWinnerCount) return true;
        return false;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
