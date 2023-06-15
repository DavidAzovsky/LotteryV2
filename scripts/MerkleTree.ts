const { MerkleTree } = require("merkletreejs");;
const keccak256 = require("keccak256");

var fs = require("fs");
var path = require("path");

const data = fs
 .readFileSync(path.join(__dirname, "./wallets.csv"), "utf8")
 .split("\n");

const leaves = data.map((x: any) => keccak256(x));
const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const root = tree.getHexRoot();

console.log("Root: ", root);
console.log(tree.toString());

// verifying merkle
for (let i = 0; i < leaves.length; i++) {
 const leaf = leaves[i];

 const proof = tree.getHexProof(leaf);

 console.log("Proof for: ", data[i]);
 console.log(proof);

 console.log(tree.verify(proof, leaf, root)); // true
}