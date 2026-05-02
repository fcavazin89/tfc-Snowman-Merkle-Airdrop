# Finding Submission #1 - Critical

## Title
Anyone Can Mint Unlimited Snowman NFTs Without Staking

## Severity
**Critical** (High Impact + High Likelihood)

## Description
The `mintSnowman()` function in `Snowman.sol` has no access control. Any external address can call this function and mint unlimited NFTs to any recipient without staking Snow tokens. This completely bypasses the airdrop mechanism and allows attackers to inflate the NFT supply infinitely.

### Vulnerable Code
```solidity
// src/Snowman.sol:36-44
function mintSnowman(address receiver, uint256 amount) external {
    for (uint256 i = 0; i < amount; i++) {
        _safeMint(receiver, s_TokenCounter);
        emit SnowmanMinted(receiver, s_TokenCounter);
        s_TokenCounter++;
    }
}
```

### Root Cause
The function is marked as `external` but has no access control modifier (like `onlyOwner`, `onlyAirdrop`, etc.). According to the protocol design, NFTs should only be minted by the `SnowmanAirdrop` contract after verifying Merkle proofs and EIP-712 signatures.

## Proof of Concept
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

## Impact
- **Infinite NFT inflation**: Attackers can mint unlimited NFTs, destroying the collection's value
- **Bypass of airdrop mechanics**: Users can get NFTs without staking Snow tokens
- **Economic collapse**: The protocol's core value proposition is broken
- **No cost attack**: Minting requires no ETH/Snow tokens

## Recommended Mitigation
Add access control to restrict minting to the airdrop contract only:

```solidity
// Add to Snowman.sol
address public s_airdropContract;

modifier onlyAirdrop() {
    if (msg.sender != s_airdropContract) {
        revert SM__NotAllowed();
    }
    _;
}

function mintSnowman(address receiver, uint256 amount) external onlyAirdrop {
    for (uint256 i = 0; i < amount; i++) {
        _safeMint(receiver, s_TokenCounter);
        emit SnowmanMinted(receiver, s_TokenCounter);
        s_TokenCounter++;
    }
}

// Set the airdrop contract in constructor or separate function
function setAirdropContract(address _airdrop) external onlyOwner {
    s_airdropContract = _airdrop;
}
```

## Location
`src/Snowman.sol:36-44`

## Validation
✅ PoC test passes  
✅ Slither detection: reentrancy-no-eth (related)  
✅ Manual review confirmed

---

**XP Expected:** 100 XP (Critical severity)
