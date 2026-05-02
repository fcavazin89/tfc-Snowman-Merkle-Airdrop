# Codehawks Missed Vulnerabilities Report

*This document contains the formatted report for the vulnerabilities identified by Codehawks that were missed in the initial submission.*

---

## [H-02] Unconsistent `MESSAGE_TYPEHASH` with standart EIP-712 declaration on contract `SnowmanAirdrop`

### Root + Impact / Description
Little typo on `MESSAGE_TYPEHASH` Declaration on `SnowmanAirdrop` contract

```solidity
// src/SnowmanAirdrop.sol
49:   bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

**Impact:**
Function `claimSnowman` never be TRUE condition.

### Proof of Concept
Applying this function at the end of `/test/TestSnowmanAirdrop.t.sol` to know what the correct and wrong digest output HASH.

Ran with command: `forge test --match-test testFrontendSignatureVerification -vvvv`

```solidity
    function testFrontendSignatureVerification() public {
        // Setup Alice for the test
        vm.startPrank(alice);
        snow.approve(address(airdrop), 1);
        vm.stopPrank();
        
        // Simulate frontend using the correct format
        bytes32 FRONTEND_MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
        
        // Domain separator used by frontend (per EIP-712)
        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Snowman Airdrop"),
                keccak256("1"),
                block.chainid,
                address(airdrop)
            )
        );
        
        // Get Alice's token amount
        uint256 amount = snow.balanceOf(alice);
        
        // Frontend creates hash using the correct format
        bytes32 structHash = keccak256(
            abi.encode(
                FRONTEND_MESSAGE_TYPEHASH,
                alice,
                amount
            )
        );
        
        // Frontend creates the final digest (per EIP-712)
        bytes32 frontendDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );
        
        // Alice signs the digest created by the frontend
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alKey, frontendDigest);
        
        // Digest created by the contract (with typo)
        bytes32 contractDigest = airdrop.getMessageHash(alice);
        
        // Display both digests for comparison
        console2.log("Frontend Digest (correct format):");
        console2.logBytes32(frontendDigest);
        console2.log("Contract Digest (with typo):");
        console2.logBytes32(contractDigest);
        
        // Compare the digests - they should differ due to the typo
        assertFalse(
            frontendDigest == contractDigest,
            "Digests should differ due to typo in MESSAGE_TYPEHASH"
        );
        
        // Attempt to claim with the signature - should fail
        vm.prank(satoshi);
        vm.expectRevert(SnowmanAirdrop.SA__InvalidSignature.selector);
        airdrop.claimSnowman(alice, AL_PROOF, v, r, s);

        assertEq(nft.balanceOf(alice), 0);
    }
```

### Recommended Mitigation
On contract `SnowmanAirdrop.sol` Line 49 applying this:

```diff
- bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
+ bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
```

---

## [M-01] DoS to a user trying to claim a Snowman

### Root + Impact / Description
Users will approve a specific amount of Snow to the `SnowmanAirdrop` and also sign a message with their address and that same amount, in order to be able to claim the NFT.

Because the current amount of Snow owned by the user is used in the verification, an attacker could forcefully send Snow to the receiver in a front-running attack, to prevent the receiver from claiming the NFT.

```solidity
function getMessageHash(address receiver) public view returns (bytes32) {
...
  // @audit HIGH An attacker could send 1 wei of Snow token to the receiver and invalidate the signature, causing the receiver to never be able to claim their Snowman
  uint256 amount = i_snow.balanceOf(receiver);

  return _hashTypedDataV4(
      keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount})))
  );
}
```

### Risk
**Likelihood:**
The attacker must purchase Snow and forcefully send it to the receiver in a front-running attack, so the likelihood is Medium.

**Impact:**
The impact is High as it could lock out the receiver from claiming forever.

### Proof of Concept
The attack consists on Bob sending an extra Snow token to Alice before Satoshi claims the NFT on behalf of Alice. To showcase the risk, the extra Snow is earned for free by Bob.

```solidity
     function testDoSClaimSnowman() public {
        assert(snow.balanceOf(alice) == 1);

        // Get alice's digest while the amount is still 1
        bytes32 alDigest = airdrop.getMessageHash(alice);
        // alice signs a message
        (uint8 alV, bytes32 alR, bytes32 alS) = vm.sign(alKey, alDigest);

        vm.startPrank(bob);
        vm.warp(block.timestamp + 1 weeks);

        snow.earnSnow();

        assert(snow.balanceOf(bob) == 2);
        snow.transfer(alice, 1);

        // Alice claim test
        assert(snow.balanceOf(alice) == 2);

        vm.startPrank(alice);
        snow.approve(address(airdrop), 1);

        // satoshi calls claims on behalf of alice using her signed message
        vm.startPrank(satoshi);
        vm.expectRevert();

        airdrop.claimSnowman(alice, AL_PROOF, alV, alR, alS);
     }
```

### Recommended Mitigation
Include the amount to be claimed in both `getMessageHash` and `claimSnowman` instead of reading it from the Snow contract. Showing only the new code in the section below:

```solidity
function claimSnowman(address receiver, uint256 amount, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
    {
        // ...

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(receiver, amount))));

        if (!MerkleProof.verify(merkleProof, i_merkleRoot, leaf)) {
            revert SA__InvalidProof();
        }

        // @audit LOW Seems like using the ERC20 permit here would allow for both the delegation of the claim and the transfer of the Snow tokens in one transaction
        i_snow.safeTransferFrom(receiver, address(this), amount); // send 

        // ...
    }
```

---

## [L-01] Missing Claim Status Check Allows Multiple Claims in SnowmanAirdrop.sol::claimSnowman

### Root + Impact / Description
**Root:** The `claimSnowman` function updates `s_hasClaimedSnowman[receiver] = true` but never checks if the user has already claimed before processing the claim, allowing users to claim multiple times if they acquire more Snow tokens.

**Impact:** Users can bypass the intended one-time airdrop limit by claiming, acquiring more Snow tokens, and claiming again, breaking the airdrop distribution model and allowing unlimited NFT minting for eligible users.

**Normal Behavior:** Airdrop mechanisms should enforce one claim per eligible user to ensure fair distribution and prevent abuse of the reward system.

**Specific Issue:** The function sets the claim status to true after processing but never validates if `s_hasClaimedSnowman[receiver]` is already true at the beginning, allowing users to claim multiple times as long as they have Snow tokens and valid proofs.

### Risk
**Likelihood: Medium**
- Users need to acquire additional Snow tokens between claims, which requires time and effort
- Users must maintain their merkle proof validity across multiple claims
- Attack requires understanding of the missing validation check

**Impact: High**
- Airdrop Abuse: Users can claim far more NFTs than intended by the distribution mechanism
- Unfair Distribution: Some users receive multiple rewards while others may receive none
- Economic Manipulation: Breaks the intended scarcity and distribution model of the NFT collection

### Proof of Concept
Add the following test to `TestSnowMan.t.sol`:

```solidity
function testMultipleClaimsAllowed() public {
        // Alice claims her first NFT
        vm.prank(alice);
        snow.approve(address(airdrop), 1);

        bytes32 aliceDigest = airdrop.getMessageHash(alice);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alKey, aliceDigest);

        vm.prank(alice);
        airdrop.claimSnowman(alice, AL_PROOF, v, r, s);

        assert(nft.balanceOf(alice) == 1);
        assert(airdrop.getClaimStatus(alice) == true);

        // Alice acquires more Snow tokens (wait for timer and earn again)
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(alice);
        snow.earnSnow();

        // Alice can claim AGAIN with new Snow tokens!
        vm.prank(alice);
        snow.approve(address(airdrop), 1);

        bytes32 aliceDigest2 = airdrop.getMessageHash(alice);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(alKey, aliceDigest2);

        vm.prank(alice);
        airdrop.claimSnowman(alice, AL_PROOF, v2, r2, s2); // Second claim succeeds!

        assert(nft.balanceOf(alice) == 2); // Alice now has 2 NFTs
    }
```

### Recommended Mitigation
Add a claim status check at the beginning of the function to prevent users from claiming multiple times.

```diff
// Add new error
+ error SA__AlreadyClaimed();

function claimSnowman(address receiver, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s)
    external
    nonReentrant
{
+   if (s_hasClaimedSnowman[receiver]) {
+       revert SA__AlreadyClaimed();
+   }
+   
    if (receiver == address(0)) {
        revert SA__ZeroAddress();
    }
    
    // Rest of function logic...
    
    s_hasClaimedSnowman[receiver] = true;
}
```

---

## [L-02] Global Timer Reset in Snow::buySnow Denies Free Claims for All Users

### Root + Impact / Description
The `Snow::buySnow` function contains a critical flaw where it resets a global timer (`s_earnTimer`) to the current block timestamp on every invocation. This timer controls eligibility for free token claims via `Snow::earnSnow()`, which requires 1 week to pass since the last timer reset. As a result:
- Any token purchase (via `buySnow`) blocks all free claims for all users for 7 days
- Malicious actors can permanently suppress free claims with micro-transactions
- Contradicts protocol documentation promising "free weekly claims per user"

**Impact:**
- Complete Denial-of-Service: Free claim mechanism becomes unusable
- Broken Protocol Incentives: Undermines core user acquisition strategy
- Economic Damage: Eliminates promised free distribution channel
- Reputation Harm: Users perceive protocol as dishonest

```solidity
    function buySnow(uint256 amount) external payable canFarmSnow {
        if (msg.value == (s_buyFee * amount)) {
            _mint(msg.sender, amount);
        } else {
            i_weth.safeTransferFrom(msg.sender, address(this), (s_buyFee * amount));
            _mint(msg.sender, amount);
        }

  @>      s_earnTimer = block.timestamp;

        emit SnowBought(msg.sender, amount);
    }
```

### Risk
**Likelihood:**
- Triggered by normal protocol usage (any purchase)
- Requires only one transaction every 7 days to maintain blockage
- Incentivized attack (low-cost disruption)

**Impact:**
- Permanent suppression of core protocol feature
- Loss of user trust and adoption
- Violates documented tokenomics

### Proof of Concept
**Attack Scenario: Permanent Free Claim Suppression**
1. Attacker calls `buySnow(1)` with minimum payment
2. `s_earnTimer` sets to current timestamp (T0)
3. All `earnSnow()` calls revert for next 7 days
4. On day 6, attacker repeats `buySnow(1)`
5. New timer reset (T1 = T0+6 days)
6. Free claims blocked until T1+7 days (total 13 days)
7. Repeat step 4 every 6 days → permanent blockage

**Test Case:**
```solidity
// Day 0: Deploy contract
snow = new Snow(...);  // s_earnTimer = 0

// UserA claims successfully
snow.earnSnow(); // Success (first claim always allowed)

// Day 1: UserB buys 1 token
snow.buySnow(1); // Resets global timer to day 1

// Day 2: UserA attempts claim
snow.earnSnow(); // Reverts! Requires day 1+7 = day 8

// Day 7: UserC buys 1 token (day 7 < day 1+7)
snow.buySnow(1); // Resets timer to day 7

// Day 8: UserA retries
snow.earnSnow(); // Still reverts! Now requires day 7+7 = day 14
```

### Recommended Mitigation
**Step 1: Remove Global Timer Reset from buySnow**
```diff
function buySnow(uint256 amount) external payable canFarmSnow {
     // ... existing payment logic ...
-     s_earnTimer = block.timestamp;
       emit SnowBought(msg.sender, amount);
}
```

**Step 2: Implement Per-User Timer in earnSnow**
```solidity
// Add new state variable
mapping(address => uint256) private s_lastClaimTime;

function earnSnow() external canFarmSnow {
    // Check per-user timer instead of global
    if (s_lastClaimTime[msg.sender] != 0 && 
        block.timestamp < s_lastClaimTime[msg.sender] + 1 weeks
    ) {
        revert S__Timer();
    }
    
    _mint(msg.sender, 1);
    s_lastClaimTime[msg.sender] = block.timestamp; // Update user-specific timer
    emit SnowEarned(msg.sender, 1); // Add missing event
}
```

**Step 3: Initialize First Claim (Constructor)**
```solidity
constructor(...) {
    // Initialize with current timestamp to prevent immediate claims
    s_lastClaimTime[address(0)] = block.timestamp;
}
```
