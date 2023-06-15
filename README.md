### Lottery Project

To test the contract run "npx hardhat test"
Here you can see some errors like below:
"ProviderError: missing trie node d50c4e62c429e597312eb394410d0c4986a3aecd286033e255b46b11a1721b39 (path ) <nil>"
To fix this issue, change hardhat.config.ts file's blockNumber + 3000000
And run "npx hardhat test" again.
Here you can see another error like below:
"Error: Trying to initialize a provider with block 19460351 but the current block is 17460560"
Change hardhat.config.ts file's blockNumber to current block - 5 (example: 17460560 - 5 = 17460555)

After you run "npx hardhat test" again, you can see the result you want.

> -- sorry for this errors, and thank you for try to understand about it.
> -- Try to find solution and remove such process asap. enjoy my project

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

### Subgraph

subgraph/winner - the subgraph to fetch the list of winners,
create and deployed subgraph in https://thegraph.com/hosted-service/subgraph/davidazovsky/winner,
but since it can be execute query through ethereum mainnet transaction, not tested.
Had a try to create subgraph of Sepolia testnet, but not done.

### Address

Ethereum Mainnet:
WETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
USDT: 0xdAC17F958D2ee523a2206206994597C13D831ec7
UniswapV2 USDT(LP token): 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852
UniswapV2Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
masterChef: 0xB2b1a37742aacfC90d06bDFe9B7A35f8826597dc
SpookyToken(RewardToken): 0xaE0dc81E68BfC2430f30A97cA62343d56aA0BE02

Ethereum Mainnet:
ChainlinkVRFCoordinator: 0xf0d54349addcf704f77ae15b96510dea15cb7952
ChainlinkVRFCoordinatorV2: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909
LinkToken: 0x514910771AF9Ca656af840dff83E8264EcF986CA
ChainlinkKeyHash: 0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805
ChainlinkFee: 2000000000000000000

Hardhat:
0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4

Rinkeby:
KeyHash: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef
Coordinator: 0x271682deb8c4e0901d1a1550ad2e64d568e69909
LinkToken: 0x514910771af9ca656af840dff83e8264ecf986ca
