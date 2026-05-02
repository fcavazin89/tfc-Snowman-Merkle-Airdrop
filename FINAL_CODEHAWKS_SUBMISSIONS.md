# Final Codehawks Submission Reports

---

## Submission Details: [H-01] Unrestricted NFT Minting in Snowman.sol

### Title
Unrestricted NFT Minting in Snowman.sol

### Impact
High

### Likelihood
High

### Scope
`src/Snowman.sol`

### Description

**Normal behavior:**
NFTs should only be minted by the `SnowmanAirdrop` contract after verifying Merkle proofs and signatures.

**Specific issue or problem:**
`Snowman::mintSnowman()` lacks access control. Any external caller can mint unlimited NFTs without staking, bypassing the protocol's core mechanics.

```solidity
// src/Snowman.sol
    // @> Vulnerability: External function without access control
    function mintSnowman(address receiver, uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(receiver, s_TokenCounter);
            s_TokenCounter++;
        }
    }
```

### Risk
Likelihood: High - No costs or conditions are required to execute the attack.

Impact: High - Infinite inflation destroys the NFT's value and renders the staking system useless.

### Proof of Concept
The following test demonstrates that an unauthorized attacker can mint 100 NFTs for free, bypassing all staking requirements:

```solidity
function testFinding1_UnrestrictedMinting() public {
    address attacker = makeAddr("attacker");
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    assert(nft.balanceOf(attacker) == 100);
}
```

### Recommended Mitigation
Implement the `onlyAirdrop` modifier to restrict minting to the authorized airdrop contract only.

```diff
+ address public s_airdropContract;
+ modifier onlyAirdrop() {
+     if (msg.sender != s_airdropContract) revert SM__NotAllowed();
+     _;
+ }
- function mintSnowman(address receiver, uint256 amount) external {
+ function mintSnowman(address receiver, uint256 amount) external onlyAirdrop {
```

---

## Submission Details: [H-02] Unconsistent `MESSAGE_TYPEHASH` with EIP-712 declaration

### Title
Unconsistent `MESSAGE_TYPEHASH` with EIP-712 declaration on contract `SnowmanAirdrop`

### Impact
High

### Likelihood
High

### Scope
`src/SnowmanAirdrop.sol`

### Description

**Normal behavior:**
The `MESSAGE_TYPEHASH` must match the standard EIP-712 declaration used by the frontend to ensure valid signature verification.

**Specific issue or problem:**
A typo exists in the `MESSAGE_TYPEHASH`. The word `address` is misspelled as `addres`.

```solidity
// src/SnowmanAirdrop.sol:49
// @> Vulnerability: 'addres' misspelled
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

### Risk
Likelihood: High - The typo is hardcoded; all standard frontend signatures will fail verification.

Impact: High - Signature-based claims are completely broken.

### Proof of Concept
This test confirms the mismatch between the contract's typehash and the standard EIP-712 format, which causes `ecrecover` to fail for valid signatures:

```solidity
    function testFrontendSignatureVerification() public {
        bytes32 CORRECT_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
        bytes32 contractTypeHash = airdrop.getMessageHash(alice);
        assertFalse(CORRECT_TYPEHASH == contractTypeHash, "Mismatch due to typo");
    }
```

### Recommended Mitigation
Fix the typo in the type hash to align with standard EIP-712 implementations.

```diff
- bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
+ bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
```

---

## Submission Details: [M-01] DoS to a user trying to claim a Snowman

### Title
DoS to a user trying to claim a Snowman via balance manipulation

### Impact
High

### Likelihood
Medium

### Scope
`src/SnowmanAirdrop.sol`

### Description

**Normal behavior:**
Users should sign a message for a fixed claim amount that remains valid regardless of minor balance changes.

**Specific issue or problem:**
Verification relies on `i_snow.balanceOf(receiver)`. An attacker can front-run a claim by sending 1 wei of Snow to the receiver, changing their balance and invalidating their signature.

```solidity
// src/SnowmanAirdrop.sol
  function getMessageHash(address receiver) public view returns (bytes32) {
    // @> Vulnerability: Uses dynamic balance manipulation
    uint256 amount = i_snow.balanceOf(receiver);
    return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount}))));
  }
```

### Risk
Likelihood: Medium - Minimal cost (1 wei) to execute a front-running attack in the mempool.

Impact: High - Permanent Denial-of-Service for targeted users attempting to claim via signature.

### Proof of Concept
This PoC simulates an attacker sending 1 wei to Alice after she signs her message, causing the subsequent claim transaction to revert:

```solidity
     function testDoSClaimSnowman() public {
        bytes32 alDigest = airdrop.getMessageHash(alice);
        (uint8 alV, bytes32 alR, bytes32 alS) = vm.sign(alKey, alDigest);
        vm.prank(bob);
        snow.transfer(alice, 1); // Front-run
        vm.expectRevert();
        airdrop.claimSnowman(alice, AL_PROOF, alV, alR, alS);
     }
```

### Recommended Mitigation
Pass `amount` as an explicit parameter to verify signatures against a fixed value rather than a dynamic balance.

```solidity
function claimSnowman(address receiver, uint256 amount, ...) external {
    // Verify against fixed amount instead of balanceOf
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(receiver, amount))));
}
```

---

## Submission Details: [L-01] Missing Claim Status Check Allows Multiple Claims

### Title
Missing Claim Status Check Allows Multiple Claims in SnowmanAirdrop.sol

### Impact
High

### Likelihood
Medium

### Scope
`src/SnowmanAirdrop.sol`

### Description

**Normal behavior:**
Airdrops must enforce a one-time claim limit per eligible user.

**Specific issue or problem:**
The `claimSnowman` function lacks a check for the `s_hasClaimedSnowman` mapping, allowing eligible users to claim multiple times if they acquire more tokens.

```solidity
// src/SnowmanAirdrop.sol
    function claimSnowman(...) external {
        // @> Vulnerability: Missing check if s_hasClaimedSnowman[receiver] is true
        // ...
        s_hasClaimedSnowman[receiver] = true;
    }
```

### Risk
Likelihood: Medium - Requires the user to acquire more tokens to satisfy the Merkle check again.

Impact: High - Allows draining the NFT collection and breaks distribution rules.

### Proof of Concept
This test shows Alice claiming one NFT, acquiring more tokens, and successfully claiming a second NFT because the contract doesn't check her claim status:

```solidity
function testMultipleClaimsAllowed() public {
    airdrop.claimSnowman(alice, AL_PROOF, v, r, s);
    snow.earnSnow(); // Alice gets more tokens
    airdrop.claimSnowman(alice, AL_PROOF, v2, r2, s2); // Succeeds
    assert(nft.balanceOf(alice) == 2);
}
```

### Recommended Mitigation
Add a check at the beginning of the function to revert if the user has already claimed.

```diff
+ if (s_hasClaimedSnowman[receiver]) revert SA__AlreadyClaimed();
```

---

## Submission Details: [L-02] Global Timer Reset in Snow::buySnow

### Title
Global Timer Reset in Snow::buySnow Denies Free Claims for All Users

### Impact
High

### Likelihood
Medium

### Scope
`src/Snow.sol`

### Description

**Normal behavior:**
Users should be able to earn free tokens independently once per week.

**Specific issue or problem:**
`buySnow` resets a global `s_earnTimer`. This blocks the `earnSnow` function for all users whenever any single user makes a purchase.

```solidity
// src/Snow.sol
    function buySnow(uint256 amount) external payable canFarmSnow {
        // @> Vulnerability: Resets global timer used by all users
        s_earnTimer = block.timestamp;
    }
```

### Risk
Likelihood: Medium - Any normal purchase resets the timer; a malicious user can block everyone for 1 wei.

Impact: High - Complete suppression of the free claim mechanism for the entire protocol.

### Proof of Concept
This scenario shows how a purchase by User B prevents User A from earning tokens for another week:

```solidity
snow.buySnow(1); // User B buys
vm.prank(userA);
snow.earnSnow(); // Reverts due to global timer reset
```

### Recommended Mitigation
Use a per-user mapping to track claim times, ensuring users' actions do not interfere with each other.

```diff
+ mapping(address => uint256) private s_lastClaimTime;
  function earnSnow() external {
-     if (block.timestamp < (s_earnTimer + 1 weeks)) revert S__Timer();
+     if (block.timestamp < (s_lastClaimTime[msg.sender] + 1 weeks)) revert S__Timer();
  }
```
