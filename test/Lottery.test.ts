import { artifacts, ethers, network, waffle } from "hardhat";
import { expect } from "chai";
import { MockProvider } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "alchemy-sdk";
const { upgrades } = require("hardhat");
import Web3 from "web3";

const { provider } = waffle;
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

async function increaseBlockTimestamp(provider: MockProvider, time: number) {
  await provider.send("evm_increaseTime", [time]);
  await provider.send("evm_mine", []);
}

describe("Lottery", async () => {
  let owner: SignerWithAddress;
  let lotteryV1: Contract;
  let lottery: Contract;

  let lotteryTicket: Contract;
  let lotteryWrapTicket: Contract;

  let vrfCoordinatorMock: Contract;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let user4: SignerWithAddress;
  let user5: SignerWithAddress;
  let user6: SignerWithAddress;
  let whiteUser: SignerWithAddress;
  let user7: SignerWithAddress;

  enum LOTTERY_STATE {
    OPEN,
    BREAK,
    CLOSE,
    CALCULATING_WINNER,
  }

  beforeEach(async () => {
    [owner, user1, user2, user3, user4, user7, whiteUser, user5, user6] =
      await ethers.getSigners();

    const merkleRoot =
      "0x8ac5c40685370eb311dc6c077cddc825e8250b78d9949e164f17334854644290";
    const kyeHash =
      "0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4";

    const vrfCoordinatorMockFactory = await ethers.getContractFactory(
      "VRFCoordinatorV2Mock"
    );

    vrfCoordinatorMock = await vrfCoordinatorMockFactory.deploy(0, 0);

    const tranaction = await vrfCoordinatorMock.createSubscription();
    const tranactionReceipt = await tranaction.wait(1);
    const subscriptionID = ethers.BigNumber.from(
      tranactionReceipt.events[0].topics[1]
    );

    await vrfCoordinatorMock.fundSubscription(
      subscriptionID,
      ethers.utils.parseEther("7")
    );

    //deploy lotteryV1
    const lotteryV1Factory = await ethers.getContractFactory("LotteryV1");
    lotteryV1 = await upgrades.deployProxy(
      lotteryV1Factory,
      [subscriptionID, vrfCoordinatorMock.address, kyeHash, 1000000000],
      { initializer: "initialize", kind: "uups" }
    );

    //upgrade to lottery
    const lotteryFactory = await ethers.getContractFactory("LotteryV2");
    lottery = await upgrades.upgradeProxy(lotteryV1, lotteryFactory, {
      gasLimit: 30000000,
    });

    await vrfCoordinatorMock.addConsumer(subscriptionID, lottery.address);

    await lottery.setWinnerNumbers(2);
    await lottery.setFeeProtocol(50);
    await lottery.setFeeRent(10);
    await lottery.setRentAmount(ethers.utils.parseEther("1"));
    await lottery.setMerkleRoot(merkleRoot);

    const lotteryTicketFactory = await ethers.getContractFactory(
      "LotteryTicket"
    );
    lotteryTicket = await lotteryTicketFactory.deploy(lottery.address);
    await lotteryTicket.deployed();

    const lotteryWTicketFactory = await ethers.getContractFactory(
      "LotteryWrappedTicket"
    );
    lotteryWrapTicket = await lotteryWTicketFactory.deploy(lottery.address);
    await lotteryWrapTicket.deployed();

    await lottery.setTickets(lotteryTicket.address, lotteryWrapTicket.address);
  });

  it("upgraded successfully", async () => {
    const whiteLength = await lottery.updated();
    expect(whiteLength).to.be.eq(true);
  });

  it("owner should initalize successfully", async () => {
    const winnerCount = await lottery.currentWinnerCount();
    const feeProtocol = await lottery.feeProtocol();
    const feeRent = await lottery.feeRent();
    const rentAmount = await lottery.rentAmount();
    const merkleRoot = await lottery.merkleRoot();

    expect(winnerCount).to.be.eq(2);
    expect(feeProtocol).to.be.eq(50);
    expect(feeRent).to.be.eq(10);
    expect(rentAmount).to.be.eq(ethers.utils.parseEther("1"));
    expect(merkleRoot).to.be.eq(
      "0x8ac5c40685370eb311dc6c077cddc825e8250b78d9949e164f17334854644290"
    );
  });

  it("only owner should initalize lottery successfully", async () => {
    await expect(lottery.connect(user1).setWinnerNumbers(3)).to.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(lottery.connect(user1).setFeeProtocol(3)).to.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(lottery.connect(user1).setFeeRent(3)).to.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(lottery.connect(user1).setRentAmount(3)).to.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(
      lottery
        .connect(user1)
        .setMerkleRoot(
          "0x8ac5c40685370eb311dc6c077cddc825e8250b78d9949e164f17334854644290"
        )
    ).to.revertedWith("Ownable: caller is not the owner");

    await expect(lottery.connect(user1).startLottery()).to.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(lottery.connect(user1).breakLottery()).to.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(lottery.connect(user1).endLottery()).to.revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  describe("whiteListed", async () => {
    it("whitelisted users are verified with merkle tree", async () => {
      // verify and add whiteUser2 with merkle tree
      const state = await lottery.verifiedWhiteListedUser(
        [
          "0xa1247d2eaf16a4115b3a4de61efe3e813903ffaa7810276770743dc17d02be60",
          "0x503b5d9a070159af0666667edee1dac09309caad80c9f8f2123debe07ca2468b",
        ],
        whiteUser.address
      );
      expect(state).to.be.eq(true);
    });

    it("only whitelisted user is verified with merkle tree", async () => {
      const state = await lottery.verifiedWhiteListedUser(
        [
          "0xa1247d2eaf16a4115b3a4de61efe3e813903ffaa7810276770743dc17d02be60",
          "0x503b5d9a070159af0666667edee1dac09309caad80c9f8f2123debe07ca2468b",
        ],
        user1.address
      );

      expect(state).to.be.eq(false);
    });
  });

  describe("start lottery", async () => {
    it("shouldnot start lottery if before one not closed", async () => {
      await lottery.startLottery();

      await expect(lottery.startLottery()).to.revertedWith(
        "Cannot start lottery"
      );
    });
    it("start lottery successfully", async () => {
      const currentTime = (await ethers.provider.getBlock("latest")).timestamp;
      await lottery.startLottery();
      const state = await lottery.lotteryState();

      expect(state).to.be.eq(LOTTERY_STATE.OPEN);
      expect(Number(await lottery.startTime())).to.be.greaterThanOrEqual(
        currentTime
      );
    });
  });

  describe("get random numbers", async () => {
    it("should get Random number successfully", async () => {
      await lottery.startLottery();
      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });

      //set WinnerCount to 1
      await lottery.setWinnerNumbers(1);

      //break lottery
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5"]
      );

      //get first lottery's winner count
      const lotteryInfo = await lottery.lotteryInfo(1);
      await expect(lotteryInfo.winnerCount).to.be.eq(1);
    });
  });

  describe("break lottery", async () => {
    it("should not break lottery if not started", async () => {
      await expect(lottery.breakLottery()).to.revertedWith(
        "Cannot break lottery"
      );
    });
    it("should not break lottery if not break time", async () => {
      await lottery.startLottery();

      await expect(lottery.breakLottery()).to.revertedWith(
        "Cannot break lottery"
      );

      await increaseBlockTimestamp(provider, 86400 * 14);
      await expect(lottery.breakLottery()).to.revertedWith(
        "Cannot break lottery"
      );
    });

    it("break lottery successfully", async () => {
      await lottery.startLottery();
      await increaseBlockTimestamp(provider, 86400 * 7);

      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });

      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      const state = await lottery.lotteryState();
      expect(state).to.be.eq(LOTTERY_STATE.BREAK);
    });
  });

  describe("end lottery", async () => {
    it("should not end lottery if not breaked", async () => {
      await lottery.startLottery();
      await expect(lottery.endLottery()).to.revertedWith("Cannot end lottery");
    });

    it("should not end lottery if not end time", async () => {
      await lottery.startLottery();

      await increaseBlockTimestamp(provider, 86400 * 7);

      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });

      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      await expect(lottery.endLottery()).to.revertedWith("Cannot end lottery");
    });

    it("end lottery successfully", async () => {
      await lottery.startLottery();

      await increaseBlockTimestamp(provider, 86400 * 7);

      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });

      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.endLottery();

      const state = await lottery.lotteryState();
      expect(state).to.be.eq(LOTTERY_STATE.CLOSE);
    });
  });

  describe("enter to lottery", async () => {
    it("should not enter if lottery not started", async () => {
      await expect(
        lottery.connect(user1).enter([], { value: 0 })
      ).to.revertedWith("Lottery not opened");
    });

    it("nft owner should not enter if rented", async () => {
      await lottery.startLottery();
      //break lottery
      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      //end lottery
      await increaseBlockTimestamp(provider, 86400 * 8);
      await lottery.endLottery();

      //start new lottery
      await lottery.startLottery();

      await lottery
        .connect(user1)
        .rentTicket(1, { value: ethers.utils.parseEther("1") }); // rent user4's ticket

      await expect(
        lottery
          .connect(user4)
          .enter([], { value: ethers.utils.parseEther("5") })
      ).to.revertedWith("Cannot enter, rented to other");
    });

    it("users enter successfully", async () => {
      await lottery.startLottery();

      await lottery
        .connect(user1)
        .enter([], { value: ethers.utils.parseUnits("5", "ether") });

      const nftCount = await lotteryTicket.ticketCount();
      const ticketPrice = await lottery.ticketsPrice(1);
      const nftOwner = await lotteryTicket.ownerOf(1);

      expect(nftCount).to.be.eq(1);
      expect(nftOwner).to.be.eq(user1.address);
      expect(ticketPrice).to.be.eq(ethers.utils.parseEther("5"));
    });
    it("whitelisted user should enter successfully", async () => {
      await lottery.startLottery();
      //function call with msg.data which contains merkle proof
      const proofArray = [
        "0xa1247d2eaf16a4115b3a4de61efe3e813903ffaa7810276770743dc17d02be60",
        "0x503b5d9a070159af0666667edee1dac09309caad80c9f8f2123debe07ca2468b",
      ];

      await lottery.connect(whiteUser).enter(proofArray);

      const lotteryInfo = await lottery.lotteryInfo(1);
      expect(lotteryInfo.depositCount).to.be.eq(1);
      expect(lotteryInfo.totalValue).to.be.eq(0);
      expect(lotteryInfo.totalAmount).to.be.eq(
        ethers.utils.parseUnits("5", "17")
      );
    });
    it("nft owner should enter successfully", async () => {
      await lottery.startLottery();
      //break lottery
      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      //end lottery
      await increaseBlockTimestamp(provider, 86400 * 8);
      await lottery.endLottery();

      await lottery.startLottery();
      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
    });

    it("new nft owner can enter successfully", async () => {
      await lottery.startLottery();

      await lottery
        .connect(user1)
        .enter([], { value: ethers.utils.parseUnits("5", "ether") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseUnits("5", "ether") });

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );
      await increaseBlockTimestamp(provider, 86400 * 8);
      await lottery.connect(owner).endLottery();

      await lottery.startLottery();
      await lotteryTicket.connect(user1).transfer(user3.address, 1);

      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseUnits("5", "ether") });

      const ticketOwner = await lotteryTicket.ownerOf(1);
      expect(ticketOwner).to.be.eq(user3.address);
      //user1 transfer ticket to user3 so user1 is new depositor
      expect(lottery.connect(user1).enter([])).to.be.revertedWith(
        "Invalid new depositor amount"
      );
    });
  });

  describe("rent", async () => {
    beforeEach(async () => {
      await lottery.startLottery();

      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("10") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("3") });
    });

    it("should not rent if deposit period ended", async () => {
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      await expect(
        lottery
          .connect(user4)
          .rentTicket(1, { value: ethers.utils.parseEther("1") })
      ).to.revertedWith("deposit period finished"); // rent user3's ticket
    });

    it("should not rent if owner deposited already", async () => {
      await expect(
        lottery
          .connect(user4)
          .rentTicket(2, { value: ethers.utils.parseEther("1") })
      ).to.revertedWith("deposited already");
    });

    it("should not rent if ticketId is not exist", async () => {
      await expect(
        lottery
          .connect(user4)
          .rentTicket(5, { value: ethers.utils.parseEther("1") })
      ).to.revertedWith("invalid ticketID");
    });

    it("should not rent if not enough ETH", async () => {
      //break lottery

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      //end lottery
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.endLottery();

      //start new lottery
      await lottery.startLottery();

      await expect(
        lottery
          .connect(user4)
          .rentTicket(2, { value: ethers.utils.parseUnits("9", 17) })
      ).to.revertedWith("invalid input amount");
    });

    it("rent successfully", async () => {
      //end lottery
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.endLottery();

      //start new lottery round and user1 can rent user2, user3, user4's ticket with paying some eth
      await lottery.startLottery();

      const balanceUser3Before = await user3.getBalance();
      const balanceUser1Before = await user1.getBalance();
      const balanceLotteryBefore = await lottery.signer.getBalance();

      const tx = await lottery
        .connect(user1)
        .rentTicket(2, { value: ethers.utils.parseEther("1") }); // rent user3's ticket
      const receipt = await tx.wait();
      const gasAmount = receipt.gasUsed.mul(tx.gasPrice);

      const balanceUser3After = await user3.getBalance();
      const balanceUser1After = await user1.getBalance();
      const balanceLotteryAfter = await lottery.signer.getBalance();

      const borrower = await lotteryWrapTicket.ownerOf(1);
      expect(borrower).to.be.eq(user1.address);

      expect(balanceLotteryAfter).eq(balanceLotteryBefore);
      expect(balanceUser3After.sub(balanceUser3Before)).to.be.eq(
        ethers.utils.parseEther("1")
      );
      expect(balanceUser1Before.sub(balanceUser1After)).to.be.eq(
        ethers.utils.parseEther("1").add(gasAmount)
      );
    });

    it("should not rent if rented", async () => {
      //end lottery

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["5", "4"]
      );

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.endLottery();

      //start new lottery round and user4 can rent user1, user2, user3's ticket with paying some eth
      await lottery.startLottery();

      await lottery
        .connect(user1)
        .rentTicket(1, { value: ethers.utils.parseEther("1") }); // rent user3's ticket

      await expect(
        lottery
          .connect(user3)
          .rentTicket(1, { value: ethers.utils.parseEther("1") })
      ).to.revertedWith("rent already"); // rent user3's ticket
    });
  });

  describe("claim", async () => {
    beforeEach(async () => {
      await lottery.startLottery();

      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      // Set random number to [3, 2], so the winner is user2, user3
      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["3", "2"]
      );

      await lottery.connect(user4).claim();

      await increaseBlockTimestamp(provider, 86400 * 8);
      await lottery.endLottery();

      await lottery.startLottery();
      await lottery
        .connect(user1)
        .rentTicket(1, { value: ethers.utils.parseEther("1") }); /// rent user4's ticket
      await lottery
        .connect(user6)
        .rentTicket(3, { value: ethers.utils.parseEther("1") }); // rent user2's ticket

      await lotteryWrapTicket.connect(user1).transfer(user7.address, 1); // user3 transfer WTicket to user5

      await lottery
        .connect(user6)
        .enter([], { value: ethers.utils.parseEther("5") });

      await lottery
        .connect(user5)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user7)
        .enter([], { value: ethers.utils.parseEther("5") });

      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();

      //Set random number to [7,3], so the winner is user5, user7
      requestID = await lottery.requestIDs(1);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["7", "3"]
      );
    });
    it("new nft owner should claim successfully", async () => {
      const balanceUser5Before = await user5.getBalance();
      const balanceLotteryBefore = await ethers.provider.getBalance(
        lottery.address
      );

      const tx = await lottery.connect(user5).claim();
      const receipt = await tx.wait();
      const gasAmount = receipt.gasUsed.mul(tx.gasPrice);

      const balanceUser5After = await user5.getBalance();
      const balanceLotteryAfter = await await ethers.provider.getBalance(
        lottery.address
      );

      expect(balanceUser5After.sub(balanceUser5Before)).to.be.eq(
        ethers.utils.parseUnits("375", "16").sub(gasAmount)
      );
      expect(balanceLotteryBefore.sub(balanceLotteryAfter)).to.be.eq(
        ethers.utils.parseUnits("375", "16")
      );
    });

    it("borrower should not claim after break period", async () => {
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.endLottery();

      await expect(lottery.connect(user7).claim()).to.revertedWith(
        "borrower cannot claim if not break period"
      );
    });
    it("borrower should not claim if not winner", async () => {
      await expect(lottery.connect(user6).claim()).to.revertedWith(
        "borrower but not winner"
      );
    });
    it("borrower should claim successfully in break period", async () => {
      const balanceUser7Before = await user7.getBalance();
      const balanceUser4Before = await lottery.balanceDepositors(user4.address);

      const tx = await lottery.connect(user7).claim();
      const receipt = await tx.wait();
      const gasAmount = receipt.gasUsed.mul(tx.gasPrice);

      const balanceUser7After = await user7.getBalance();
      const balanceUser4After = await lottery.balanceDepositors(user4.address);

      expect(balanceUser7After.sub(balanceUser7Before)).to.be.eq(
        ethers.utils.parseUnits("3375", "15").sub(gasAmount)
      );
      expect(balanceUser4After.sub(balanceUser4Before)).to.be.eq(
        ethers.utils.parseUnits("375", "15")
      );
    });

    it("owner should claim before period if borrower is not winner", async () => {
      await lottery.connect(user2).claim();
    });

    it("owner should not claim until borrower(the winner) claims in break period", async () => {
      await expect(lottery.connect(user4).claim()).to.revertedWith(
        "borrower not claimed, he is winner"
      );
    });

    it("owner should claim all reward if borrower(the winner) claims in break period", async () => {
      // end lottery
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.endLottery();

      const balanceUser7Before = await user7.getBalance();
      const balanceUser4Before = await user4.getBalance();

      const tx = await lottery.connect(user4).claim();
      const receipt = await tx.wait();
      const gasAmount = receipt.gasUsed.mul(tx.gasPrice);

      const balanceUser7After = await user7.getBalance();
      const balanceUser4After = await user4.getBalance();

      expect(balanceUser7After.sub(balanceUser7Before)).to.be.eq(0);
      expect(balanceUser4After.sub(balanceUser4Before)).to.be.eq(
        ethers.utils.parseUnits("375", "16").sub(gasAmount)
      );
    });
  });
  describe("get function", async () => {
    beforeEach(async () => {
      await lottery.startLottery();

      await lottery
        .connect(user4)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user3)
        .enter([], { value: ethers.utils.parseEther("5") });
      await lottery
        .connect(user2)
        .enter([], { value: ethers.utils.parseEther("5") });
    });
    it("should not get winner addresses if lotteryID is invalid", async () => {
      await expect(lottery.getWinnerAddress(10)).revertedWith(
        "nvalid lottery or cannot get winners after break period"
      );
    });
    it("should not get current winner addresses if not break period", async () => {
      await expect(lottery.getWinnerAddress(1)).revertedWith(
        "nvalid lottery or cannot get winners after break period"
      );
    });
    it("should get winner addresses successfully", async () => {
      await increaseBlockTimestamp(provider, 86400 * 7);
      await lottery.breakLottery();
      // Set random number to [3, 2], so the winner is user2, user3
      let requestID = await lottery.requestIDs(0);
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        requestID,
        lottery.address,
        ["3", "2"]
      );

      const winnerAddress = await lottery.getWinnerAddress(1);
    });
  });
});
