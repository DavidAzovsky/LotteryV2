//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2Upgradeable.sol";

contract LotteryV1 is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721Upgradeable,
    VRFConsumerBaseV2Upgradeable
{
    bytes32 internal keyHash;
    uint256[] public requestIDs;
    uint256 internal feeChainlink;
    uint64 subscriptionId;
    VRFCoordinatorV2Interface COORDINATOR;

    bytes32 internal merkleRoot;

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
    mapping(uint256 => TicketInfo) public ticketsInfo;
    mapping(address => uint256) public balanceDepositors;

    //LotteryInfo
    struct LotteryInfo {
        uint256 depositCount;
        uint256 totalValue;
        uint256 winnerCount;
        mapping(uint256 => address) depositors;
        mapping(address => uint256) amount;
        mapping(uint256 => address) winners;
        uint256 totalAmount;
    }

    mapping(uint256 => LotteryInfo) public lotteryInfo;
    uint256 public lotteryID;

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
    event UpdateWinners(uint256, address[]);

    function initialize(
        bytes32 _merkleRoot,
        uint64 _subscriptionId,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _fee
    ) external initializer {
        __ERC721_init("Lottery Ticket", "Lottery");
        __Ownable_init();
        __UUPSUpgradeable_init();
        __VRFConsumerBaseV2Upgradeable_init(_vrfCoordinator);
        merkleRoot = _merkleRoot;
        keyHash = _keyHash;
        feeChainlink = _fee;

        subscriptionId = _subscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        lotteryState = LOTTERY_STATE.CLOSE;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function startLottery() external onlyOwner {
        require(lotteryState == LOTTERY_STATE.CLOSE, "Cannot start lottery");

        // Update lotteryInfo
        lotteryState = LOTTERY_STATE.OPEN;
        lotteryID++;
        startTime = block.timestamp;
    }

    function depositorState(
        address user
    ) public view returns (USER_STATE state, int256 id) {
        uint i;
        for (i = 0; i < holderCount; i++) {
            if (ticketsInfo[i].owner == user) {
                state = USER_STATE.OWNER;
                id = int(i);
                break;
            }
            if (ticketsInfo[i].borrower == user) {
                state = USER_STATE.BORROWER;
                id = int(i);
                break;
            }
        }
        if (i >= holderCount) {
            state = USER_STATE.NEW_DEPOSITOR;
            id = int(holderCount);
        }

        //check if whitelisted user
        uint j;
        for (j = 0; j < whiteListedUsers.length; j++)
            if (whiteListedUsers[j] == user) break;
        if (j < whiteListedUsers.length) {
            state = USER_STATE.WHITELISTED;
            id = -1;
        }
    }

    function enter() external payable nonReentrant {
        require(lotteryState == LOTTERY_STATE.OPEN, "Lottery not opened");

        // confirm the msg.sender is nft Owner, borrower, whiteListed user, or new depositor
        (USER_STATE state, int256 id) = depositorState(msg.sender);
        uint index = uint256(id);

        if (state == USER_STATE.WHITELISTED) {
            lotteryInfo[lotteryID].amount[msg.sender] = 0.5 ether;
        }
        if (state == USER_STATE.OWNER) {
            require(
                ticketsInfo[index].borrower == address(0),
                "Cannot enter, rented to other"
            );
            lotteryInfo[lotteryID].amount[msg.sender] =
                msg.value +
                ticketsInfo[index].ticketPrice;
        }
        if (state == USER_STATE.BORROWER) {
            lotteryInfo[lotteryID].amount[msg.sender] =
                msg.value +
                ticketsInfo[index].ticketPrice;
        }
        if (state == USER_STATE.NEW_DEPOSITOR) {
            TicketInfo memory ticket;
            ticket.ticketPrice = msg.value;
            ticket.owner = msg.sender;
            ticketsInfo[holderCount] = ticket;

            lotteryInfo[lotteryID].amount[msg.sender] = msg.value;
            // todo mint nft
            _safeMint(msg.sender, holderCount);
            holderCount++;
        }

        lotteryInfo[lotteryID].depositors[
            lotteryInfo[lotteryID].depositCount++
        ] = msg.sender;

        lotteryInfo[lotteryID].totalAmount += lotteryInfo[lotteryID].amount[
            msg.sender
        ];
        lotteryInfo[lotteryID].totalValue += msg.value;
    }

    function rentTicket(uint256 ticketID) external payable nonReentrant {
        require(lotteryState == LOTTERY_STATE.OPEN, "deposit period finished");
        require(ticketsInfo[ticketID].borrower == address(0), "rent already");
        require(ticketID < holderCount, "invalid ticketID");

        for (uint i = 0; i < lotteryInfo[lotteryID].depositCount; i++) {
            if (
                lotteryInfo[lotteryID].depositors[i] ==
                ticketsInfo[ticketID].owner
            ) revert("deposited already");
        }

        require(msg.value >= rentAmount, "invalid input amount");

        ticketsInfo[ticketID].borrower = msg.sender;

        payable(ticketsInfo[ticketID].owner).transfer(rentAmount);
    }

    function breakLottery() public onlyOwner {
        require(
            lotteryState == LOTTERY_STATE.OPEN &&
                (block.timestamp >= startTime + DEPOSIT_PERIOD) &&
                block.timestamp <= (startTime + DEPOSIT_PERIOD + BREAK_PERIOD),
            "Cannot break lottery"
        );

        lotteryState = LOTTERY_STATE.CALCULATING_WINNER;
        requestRandomNumbers();
    }

    function endLottery() public onlyOwner {
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

                // if borrower is winner
                if (j < currentWinnerCount) {
                    uint256 reward = (lotteryInfo[lotteryID].totalValue *
                        (100 - feeProtocol)) /
                        currentWinnerCount /
                        100;
                    balanceDepositors[ticketsInfo[i].owner] += reward;
                }
            }
        }
    }

    function isWinner(address user) public view returns (uint256) {
        uint256 i;
        for (i = 0; i < currentWinnerCount; i++)
            if (lotteryInfo[lotteryID].winners[i] == user) break;

        return i;
    }

    //Claim rewards for Winner
    function claim() public nonReentrant {
        (USER_STATE state, int id) = depositorState(msg.sender);
        uint index = uint256(id);

        if (state == USER_STATE.BORROWER) {
            require(
                lotteryState == LOTTERY_STATE.BREAK,
                "borrower cannot claim if not break period"
            );

            uint256 i = isWinner(msg.sender);
            // if borrower is not winner, then revert
            require(i < currentWinnerCount, "borrower but not winner");

            // send feeRent percent of reward to nft owner and borrower gets rest amount
            uint256 reward = (lotteryInfo[lotteryID].totalValue *
                (100 - feeProtocol)) /
                currentWinnerCount /
                100;

            // add reward to nft owner's reward balance
            balanceDepositors[ticketsInfo[index].owner] +=
                (reward * feeRent) /
                100;
            // burn wrapped nft
            ticketsInfo[index].borrower = address(0);
            //transfer reward to borrower
            payable(msg.sender).transfer((reward * (100 - feeRent)) / 100);
        } else {
            // if nft owner's borrower is winner
            uint256 i = isWinner(ticketsInfo[index].borrower);
            if (
                ticketsInfo[index].borrower != address(0) &&
                (i < currentWinnerCount) &&
                lotteryState == LOTTERY_STATE.BREAK
            ) revert("borrower not claimed, he is winner");

            ticketsInfo[index].borrower = address(0);
            uint reward = balanceDepositors[msg.sender];
            balanceDepositors[msg.sender] = 0;
            payable(msg.sender).transfer(reward);
        }
    }

    function requestRandomNumbers() internal {
        // require(
        //     LINK.balanceOf(address(this)) >= feeChainlink,
        //     "Not enough LINK to fulfill request"
        // );
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
            lotteryInfo[lotteryID].depositCount
        );

        uint256 totalWeight = lotteryInfo[lotteryID].totalAmount;
        for (uint i = 0; i < depositors.length; i++)
            depositors[i] = lotteryInfo[lotteryID].depositors[i];

        for (uint i = 0; i < currentWinnerCount; i++) {
            uint256 rand = uint256(
                keccak256(abi.encodePacked(randomWords[i]))
            ) % totalWeight;

            uint256 weightSum = 0;
            uint j;
            for (j = 0; j < depositors.length; j++) {
                weightSum += lotteryInfo[lotteryID].amount[depositors[j]];
                if (rand < weightSum) {
                    lotteryInfo[lotteryID].winners[
                        lotteryInfo[lotteryID].winnerCount++
                    ] = depositors[j];
                    break;
                }
            }

            //IF not borrower, add reward balance to balanceDepositors
            (USER_STATE user, ) = depositorState(depositors[j]);
            if (user != USER_STATE.BORROWER)
                balanceDepositors[depositors[j]] +=
                    (lotteryInfo[lotteryID].totalValue * (100 - feeProtocol)) /
                    currentWinnerCount /
                    100;

            totalWeight -= lotteryInfo[lotteryID].amount[depositors[j]];
            delete depositors[j];
        }
        lotteryState = LOTTERY_STATE.BREAK;

        // emit UpdateWinners event
        address[] memory winnerAddress = new address[](currentWinnerCount);
        for (uint i = 0; i < currentWinnerCount; i++)
            winnerAddress[i] = lotteryInfo[lotteryID].winners[i];

        emit UpdateWinners(lotteryID, winnerAddress);
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

    function verifyWhitelistedUser(
        bytes32[] memory proof,
        address user
    ) public onlyOwner {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        if (MerkleProofUpgradeable.verify(proof, merkleRoot, leaf))
            whiteListedUsers.push(user);
    }

    function getWinnerAddress(
        uint _lotteryID
    ) external returns (address[] memory) {
        require(
            (_lotteryID < lotteryID) ||
                (_lotteryID == lotteryID &&
                    lotteryState == LOTTERY_STATE.BREAK),
            "invalid lottery or cannot get winners after break period"
        );
        address[] memory winnerAddress;
        winnerAddress = new address[](lotteryInfo[_lotteryID].winnerCount);
        for (uint i = 0; i < lotteryInfo[_lotteryID].winnerCount; i++)
            winnerAddress[i] = lotteryInfo[lotteryID].winners[i];
        return winnerAddress;
    }
}
