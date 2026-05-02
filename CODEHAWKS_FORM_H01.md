# Description
The `Snowman` contract implements a `mintSnowman` function intended to be called by the `SnowmanAirdrop` contract upon successful verification of staking and Merkle proofs. However, the current implementation lacks any access control mechanisms or caller verification.

Specifically, the `mintSnowman()` function is marked as `external` but does not include any modifiers (such as `onlyOwner` or a custom `onlyAirdrop`) to restrict who can trigger the minting process. Consequently, any address on the network can call this function directly to mint an arbitrary number of Snowman NFTs to any recipient address. This bypasses the entire staking requirement and Merkle-based distribution logic.

```solidity
// src/Snowman.sol

    // @> Vulnerability: The function is external and lacks any access control modifiers.
    function mintSnowman(address receiver, uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(receiver, s_TokenCounter);
            emit SnowmanMinted(receiver, s_TokenCounter);
            s_TokenCounter++;
        }
    }
```

# Risk
## Likelihood: High
The vulnerability is publicly accessible on the blockchain and requires no special state, permissions, or expensive prerequisites to exploit. Any user can trigger the minting process at any time.

## Impact: High
The flaw allows for infinite inflation of the Snowman NFT collection. An attacker can mint the entire supply for free, destroying the rarity and economic value of the NFTs and rendering the protocol's intended staking and airdrop mechanism completely obsolete.

# Proof of Concept
The following Proof of Concept demonstrates how an attacker can exploit the missing access control. By invoking `mintSnowman` directly from a random "attacker" address, the attacker successfully mints 100 NFTs without providing any Snow tokens or Merkle proofs.

```solidity
function testFinding1_UnrestrictedMinting() public {
    address attacker = makeAddr("attacker");
    uint256 initialCounter = nft.getTokenCounter();
    
    // Attacker calls the mint function directly, bypassing the airdrop contract
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    
    // Verification: The attacker now owns 100 NFTs for zero cost
    assert(nft.balanceOf(attacker) == 100);
    assert(nft.getTokenCounter() == initialCounter + 100);
}
```

# Recommended Mitigation
Restructure the `Snowman` contract to include an access control mechanism. Define a privileged address (the `SnowmanAirdrop` contract) and restrict the `mintSnowman` function to be callable only by that address.

```diff
// src/Snowman.sol

+ address public s_airdropContract;
+ 
+ error SM__NotAllowed();
+ 
+ modifier onlyAirdrop() {
+     if (msg.sender != s_airdropContract) {
+         revert SM__NotAllowed();
+     }
+     _;
+ }

- function mintSnowman(address receiver, uint256 amount) external {
+ function mintSnowman(address receiver, uint256 amount) external onlyAirdrop {
      for (uint256 i = 0; i < amount; i++) {
          _safeMint(receiver, s_TokenCounter);
          emit SnowmanMinted(receiver, s_TokenCounter);
          s_TokenCounter++;
      }
  }

+ function setAirdropContract(address _airdrop) external onlyOwner {
+     s_airdropContract = _airdrop;
+ }
```
