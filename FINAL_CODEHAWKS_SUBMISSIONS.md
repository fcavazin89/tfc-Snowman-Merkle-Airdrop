# Final Codehawks Submission Reports

---

## [H-01] Unrestricted NFT Minting in Snowman.sol

**Description:** `Snowman::mintSnowman()` lacks access control. Any address can mint unlimited NFTs without staking, bypassing protocol mechanics.

```solidity
function mintSnowman(address receiver, uint256 amount) external { // @> No access control
    for (uint256 i = 0; i < amount; i++) {
        _safeMint(receiver, s_TokenCounter);
        s_TokenCounter++;
    }
}
```

**Risk:** High (Likelihood: High / Impact: High). Infinite inflation destroys NFT value and renders staking useless.

**Proof of Concept:** An unauthorized attacker mints 100 NFTs for free:
```solidity
function testExploit() public {
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    assert(nft.balanceOf(attacker) == 100);
}
```

**Recommended Mitigation:** Restrict `mintSnowman` to the authorized airdrop contract via a modifier.
```diff
+ modifier onlyAirdrop() { if (msg.sender != s_airdropContract) revert(); _; }
- function mintSnowman(...) external {
+ function mintSnowman(...) external onlyAirdrop {
```

---

## [H-02] MESSAGE_TYPEHASH Typo Breaks EIP-712 Signatures

**Description:** `MESSAGE_TYPEHASH` misspells `address` as `addres`, causing all standard frontend signatures to fail verification.

```solidity
// @> typo 'addres'
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

**Risk:** High (Likelihood: High / Impact: High). Signature-based claims are permanently broken.

**Proof of Concept:** The contract's hash differs from the standard EIP-712 format used by wallets:
```solidity
function testTypo() public {
    bytes32 CORRECT = keccak256("SnowmanClaim(address receiver, uint256 amount)");
    assertFalse(CORRECT == airdrop.getMessageHash(alice));
}
```

**Recommended Mitigation:** Fix the spelling of `address` in the type hash constant.
```diff
- keccak256("SnowmanClaim(addres receiver, uint256 amount)");
+ keccak256("SnowmanClaim(address receiver, uint256 amount)");
```

---

## [M-01] DoS via Balance Manipulation (Front-running)

**Description:** `getMessageHash` uses dynamic `balanceOf(receiver)`. An attacker can front-run a claim by sending 1 wei to the user, invalidating their signature.

```solidity
function getMessageHash(address receiver) public view returns (bytes32) {
    uint256 amount = i_snow.balanceOf(receiver); // @> Manipulatable via front-running
    return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount}))));
}
```

**Risk:** High (Likelihood: Medium / Impact: High). Targeted Denial-of-Service for signature-based claims at near-zero cost.

**Proof of Concept:** Attacker sends 1 wei to Alice after she signs, causing her transaction to revert:
```solidity
function testDoS() public {
    bytes32 digest = airdrop.getMessageHash(alice);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(alKey, digest);
    vm.prank(bob); snow.transfer(alice, 1); // Front-run
    vm.expectRevert(); airdrop.claimSnowman(alice, proof, v, r, s);
}
```

**Recommended Mitigation:** Pass `amount` as a parameter to ensure signatures are verified against a fixed value.
```solidity
function claimSnowman(address receiver, uint256 amount, ...) external { ... }
```

---

## [L-01] Missing Claim Status Check Allows Multiple Claims

**Description:** `claimSnowman` updates `s_hasClaimedSnowman` but never checks it, allowing users to claim multiple times by acquiring more tokens.

```solidity
function claimSnowman(...) external {
    // @> Missing check for s_hasClaimedSnowman[receiver]
    s_hasClaimedSnowman[receiver] = true;
}
```

**Risk:** High (Likelihood: Medium / Impact: High). Drains NFT supply and violates airdrop distribution rules.

**Proof of Concept:** Alice successfully claims two NFTs by earning tokens between transactions:
```solidity
function testMultipleClaims() public {
    airdrop.claimSnowman(alice, ...);
    snow.earnSnow();
    airdrop.claimSnowman(alice, ...); // Succeeds again
}
```

**Recommended Mitigation:** Check the claim status mapping at the start of the function.
```diff
+ if (s_hasClaimedSnowman[receiver]) revert AlreadyClaimed();
```

---

## [L-02] Global Timer Reset Blocks Free Claims

**Description:** `buySnow` resets the global `s_earnTimer`, blocking `earnSnow` for all users whenever any single user makes a purchase.

```solidity
function buySnow(...) external payable {
    s_earnTimer = block.timestamp; // @> Blocks everyone for 1 week
}
```

**Risk:** High (Likelihood: Medium / Impact: High). Complete suppression of the free claim mechanism.

**Proof of Concept:** User B's purchase prevents User A from earning tokens for a week:
```solidity
snow.buySnow(1);
vm.prank(userA);
snow.earnSnow(); // Reverts
```

**Recommended Mitigation:** Use a mapping to track `s_lastClaimTime` per user instead of a global timer.
```diff
+ mapping(address => uint256) private s_lastClaimTime;
- if (block.timestamp < s_earnTimer + 1 weeks) revert();
+ if (block.timestamp < s_lastClaimTime[msg.sender] + 1 weeks) revert();
```
