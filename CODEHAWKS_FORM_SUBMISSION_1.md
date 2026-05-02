## Description

**Normal behavior:**
According to the protocol design, NFTs should only be minted by the `SnowmanAirdrop` contract after properly verifying Merkle proofs, EIP-712 signatures, and staking Snow tokens.

**Specific issue or problem:**
The `mintSnowman()` function in `Snowman.sol` lacks access control modifiers. Any external address can call this function directly and mint unlimited NFTs to any recipient without staking Snow tokens, completely bypassing the airdrop mechanism.

```solidity
// src/Snowman.sol

    // @> Vulnerability: The function is marked as `external` but has no access control modifier restricting it to the airdrop contract
    function mintSnowman(address receiver, uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(receiver, s_TokenCounter);
            emit SnowmanMinted(receiver, s_TokenCounter);
            s_TokenCounter++;
        }
    }
```

## Risk

**Likelihood:**
High
- Reason 1: Any external user or contract can directly call `mintSnowman()` at any given time since there are no checks preventing them.
- Reason 2: The attack requires no special conditions, state setup, or cost (no ETH/Snow tokens needed).

**Impact:**
High
- Impact 1: Infinite NFT inflation occurs, breaking the collection's core value proposition and destroying the protocol's economy.
- Impact 2: The entire airdrop and staking mechanics are rendered useless as users can acquire the NFTs for free.

## Proof of Concept

This vulnerability can be exploited by calling the `mintSnowman()` function directly from any address:

```solidity
function testFinding1_UnrestrictedMinting() public {
    address attacker = makeAddr("attacker");
    uint256 initialCounter = nft.getTokenCounter();
    
    // Attacker mints 100 NFTs without staking any Snow tokens
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    
    // Verify attacker received all 100 NFTs
    assert(nft.balanceOf(attacker) == 100);
    assert(nft.getTokenCounter() == initialCounter + 100);
    
    // Attacker can repeat this process unlimited times
    vm.prank(attacker);
    nft.mintSnowman(attacker, 1000);
    assert(nft.balanceOf(attacker) == 1100);
}
```

## Recommended Mitigation

Add access control to ensure that only the airdrop contract can mint NFTs.

```diff
// src/Snowman.sol

+ address public s_airdropContract;
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

+ // Set the airdrop contract in constructor or a separate initialization function
+ function setAirdropContract(address _airdrop) external onlyOwner {
+     s_airdropContract = _airdrop;
+ }
```
