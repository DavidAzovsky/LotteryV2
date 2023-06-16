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
    address[] public whiteListedUsers;

    uint256 public startTime;

    struct TicketInfo {
        uint256 ticketPrice;
        address owner;
        address borrower;
    }

    //Ticket NFT holders
    uint256 public holderCount;
    mapping(uint => TicketInfo) public ticketsInfo;
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

    enum USER_STATE {
        OWNER,
        BORROWER,
        WHITELISTED,
        NEW_DEPOSITOR
    }

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
        if (data.length > 0) {
            bytes32[] memory proof = data;
            lotteryInfo[lotteryId].whiteListed[
                msg.sender
            ] = verifiedWhiteListedUser(proof, msg.sender);
        }

        // confirm the msg.sender is nft Owner, borrower, whiteListed user, or new depositor
        USER_STATE state = depositorState(msg.sender);

        if (state == USER_STATE.WHITELISTED) {
            lotteryInfo[lotteryId].amount[msg.sender] = 0.5 ether;
        }
        if (state == USER_STATE.OWNER) {
            uint ticketId = ticket.ticketId(msg.sender);
            require(
                ticketsInfo[ticketId].borrower == address(0),
                "Cannot enter, rented to other"
            );
            lotteryInfo[lotteryId].amount[msg.sender] =
                msg.value +
                ticketsInfo[ticketId].ticketPrice;
        }
        if (state == USER_STATE.BORROWER) {
            uint ticketId = wTicket.ticketId(msg.sender);
            lotteryInfo[lotteryId].amount[msg.sender] =
                msg.value +
                ticketsInfo[ticketId].ticketPrice;
        }
        if (state == USER_STATE.NEW_DEPOSITOR) {
            TicketInfo memory ticketInfo;
            ticketInfo.ticketPrice = msg.value;
            ticketInfo.owner = msg.sender;
            ticketsInfo[holderCount] = ticketInfo;

            lotteryInfo[lotteryId].amount[msg.sender] = msg.value;

            ticket.mintToken(msg.sender);
            holderCount++;
        }

        lotteryInfo[lotteryId].depositors[
            lotteryInfo[lotteryId].depositCount++
        ] = msg.sender;

        lotteryInfo[lotteryId].totalAmount += lotteryInfo[lotteryId].amount[
            msg.sender
        ];
        lotteryInfo[lotteryId].totalValue += msg.value;
    }

    function rentTicket(uint256 ticketId) external payable nonReentrant {
        require(lotteryState == LOTTERY_STATE.OPEN, "deposit period finished");
        require(ticketsInfo[ticketId].borrower == address(0), "rent already");
        require(ticketId < holderCount, "invalid ticketID");

        for (uint i = 0; i < lotteryInfo[lotteryId].depositCount; i++) {
            if (
                lotteryInfo[lotteryId].depositors[i] ==
                ticketsInfo[ticketId].owner
            ) revert("deposited already");
        }

        require(msg.value >= rentAmount, "invalid input amount");

        ticketsInfo[ticketId].borrower = msg.sender;

        //mint wrapped ticket
        wTicket.mintToken(msg.sender, ticketId);

        payable(ticketsInfo[ticketId].owner).transfer(rentAmount);
    }

    //Claim rewards for Winner
    function claim() external nonReentrant {
        USER_STATE state = depositorState(msg.sender);

        require(
            state != USER_STATE.NEW_DEPOSITOR,
            "borrower cannot claim if not break period"
        );
        if (state == USER_STATE.BORROWER) {
            uint256 i = isWinner(msg.sender);
            // if borrower is not winner, then revert
            require(i < currentWinnerCount, "borrower but not winner");

            uint ticketId = wTicket.ticketId(msg.sender);

            // send feeRent percent of reward to nft owner and borrower gets rest amount
            uint256 reward = (lotteryInfo[lotteryId].totalValue *
                (100 - feeProtocol)) /
                currentWinnerCount /
                100;

            // add reward to nft owner's reward balance
            balanceDepositors[ticketsInfo[ticketId].owner] +=
                (reward * feeRent) /
                100;
            // burn wrapped nft
            wTicket.burnToken(msg.sender);
            ticketsInfo[ticketId].borrower = address(0);
            //transfer reward to borrower
            payable(msg.sender).transfer((reward * (100 - feeRent)) / 100);
        } else {
            // if nft owner's borrower is winner
            uint256 ticketId = ticket.ticketId(msg.sender);
            uint256 i = isWinner(ticketsInfo[ticketId].borrower);
            if (
                ticketsInfo[ticketId].borrower != address(0) &&
                (i < currentWinnerCount) &&
                lotteryState == LOTTERY_STATE.BREAK
            ) revert("borrower not claimed, he is winner");

            ticketsInfo[ticketId].borrower = address(0);
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
        for (uint i = 0; i < holderCount; i++) {
            if (ticketsInfo[i].borrower != address(0)) {
                uint j = isWinner(ticketsInfo[i].borrower);

                // if borrower is winner, nft owner claim all reward
                if (j < currentWinnerCount) {
                    uint256 reward = (lotteryInfo[lotteryId].totalValue *
                        (100 - feeProtocol)) /
                        currentWinnerCount /
                        100;
                    balanceDepositors[ticketsInfo[i].owner] += reward;
                }

                //burn wrapped nft
                wTicket.burnToken(ticketsInfo[i].borrower);
                ticketsInfo[i].borrower = address(0);
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

    function depositorState(
        address user
    ) public view returns (USER_STATE state) {
        if (lotteryInfo[lotteryId].whiteListed[user]) {
            state = USER_STATE.WHITELISTED;
        } else if (ticketsInfo[ticket.ticketId(user)].owner == user) {
            state = USER_STATE.OWNER;
        } else if (ticketsInfo[wTicket.ticketId(user)].borrower == user) {
            state = USER_STATE.BORROWER;
        } else state = USER_STATE.NEW_DEPOSITOR;
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
        address[] memory depositors = new address[](
            lotteryInfo[lotteryId].depositCount
        );

        uint256 totalWeight = lotteryInfo[lotteryId].totalAmount;
        for (uint i = 0; i < depositors.length; i++)
            depositors[i] = lotteryInfo[lotteryId].depositors[i];

        for (uint i = 0; i < currentWinnerCount; i++) {
            uint256 rand = uint256(
                keccak256(abi.encodePacked(randomWords[i]))
            ) % totalWeight;

            uint256 weightSum = 0;
            uint j;
            for (j = 0; j < depositors.length; j++) {
                weightSum += lotteryInfo[lotteryId].amount[depositors[j]];
                if (rand < weightSum) {
                    lotteryInfo[lotteryId].winners[
                        lotteryInfo[lotteryId].winnerCount++
                    ] = depositors[j];
                    break;
                }
            }

            //IF not borrower, add reward balance to balanceDepositors
            USER_STATE user = depositorState(depositors[j]);
            if (user != USER_STATE.BORROWER)
                balanceDepositors[depositors[j]] +=
                    (lotteryInfo[lotteryId].totalValue * (100 - feeProtocol)) /
                    currentWinnerCount /
                    100;

            totalWeight -= lotteryInfo[lotteryId].amount[depositors[j]];
            delete depositors[j];
        }
        lotteryState = LOTTERY_STATE.BREAK;

        // emit UpdateWinners event
        address[] memory winnerAddress = new address[](currentWinnerCount);
        for (uint i = 0; i < currentWinnerCount; i++)
            winnerAddress[i] = lotteryInfo[lotteryId].winners[i];

        emit UpdateWinners(lotteryId, winnerAddress);
    }

    function isWinner(address user) internal view returns (uint256) {
        uint256 i;
        for (i = 0; i < currentWinnerCount; i++)
            if (lotteryInfo[lotteryId].winners[i] == user) break;

        return i;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
