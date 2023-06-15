# LotteryV2 Project
A smart contract which allows users to buy lottery ticket as NFT. 
N random winners are chosen by the owner and share the same amount of rewards to them.

## chainlink VRF

Get random number with VRFConsumerBase not VRFConsumberBaseV2 for reasons of randomWords[] % WinnerCount can be duplicated
For that reason get random numbers one by one with VRFConsumberBase not get N random numbers from VRFConsumerBaseV2.
Test random number generate with VRFCoordinatorMock.

## merkle tree generate

scripts/MerkleTree.ts - the script that generate merkle tree of whitelisted users from wallets.csv.
Verify whitelisted users from merkle tree.

## UUPS upgradeable

upgrade LotteryV1 to LotteryV2 with added function - getWhiteListLength
using uups pattern.


# Address

## Ethereum Mainnet:
WETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
UniswapV2Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

## Ethereum Mainnet:
ChainlinkVRFCoordinator: 0xf0d54349addcf704f77ae15b96510dea15cb7952
ChainlinkVRFCoordinatorV2: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909
LinkToken: 0x514910771AF9Ca656af840dff83E8264EcF986CA
ChainlinkKeyHash: 0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805
ChainlinkFee: 2000000000000000000

## Hardhat:
0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4

## Rinkeby:
KeyHash: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef
Coordinator: 0x271682deb8c4e0901d1a1550ad2e64d568e69909
LinkToken: 0x514910771af9ca656af840dff83e8264ecf986ca
