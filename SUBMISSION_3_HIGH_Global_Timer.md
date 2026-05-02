# Finding Submission #3 - High

## Title
Global earnSnow Timer Blocks All Users

## Severity
**High** (Medium Impact + High Likelihood)

## Description
The `s_earnTimer` variable in `Snow.sol` is a **global state variable**, not per-user. When any user calls `earnSnow()`, the timer is updated to current timestamp, blocking **ALL** other users from calling `earnSnow()` for a week, even if they have never earned before.

### Vulnerable Code
```solidity
// src/Snow.sol:29
uint256 private s_earnTimer; // Global, not per-user!

// src/Snow.sol:87
s_earnTimer = block.timestamp; // Overwrites for ALL users
```

### Root Cause
The timer should track per-user cooldowns, but instead uses a single global variable. This is a logical flaw in the farming mechanism.

## Proof of Concept
```solidity
function testFinding3_GlobalTimerBlocksAll() public {
    address charlie = makeAddr("charlie");
    
    // Alice earns snow (sets global timer)
    vm.prank(alice);
    snow.earnSnow();
    
    // Bob (who never earned) tries to earn
    // He should be able to, but is blocked by Alice's timer
    vm.prank(bob);
    vm.expectRevert(Snow.S__Timer.selector);
    snow.earnSnow();
    
    // Even charlie (new user) is blocked
    vm.prank(charlie);
    vm.expectRevert(Snow.S__Timer.selector);
    snow.earnSnow();
    
    // Only after 1 week passes can others earn
    vm.warp(block.timestamp + 1 weeks + 1);
    
    vm.prank(charlie);
    snow.earnSnow(); // Now works
    assert(snow.balanceOf(charlie) == 1);
}
```

## Impact
- **Unfair farming**: One active user blocks all others
- **DoS for farming**: Users cannot earn Snow tokens if anyone else recently farmed
- **Poor UX**: Users get unexpected reverts
- **Centralization risk**: A malicious user could keep calling `earnSnow()` weekly to block others

## Recommended Mitigation
Change to per-user tracking:

```solidity
// Replace global timer with mapping
mapping(address => uint256) private s_lastEarnTime;

function earnSnow() external canFarmSnow {
    if (s_lastEarnTime[msg.sender] != 0 && 
        block.timestamp < (s_lastEarnTime[msg.sender] + 1 weeks)) {
        revert S__Timer();
    }
    _mint(msg.sender, 1);
    s_lastEarnTime[msg.sender] = block.timestamp;
}
```

## Location
`src/Snow.sol:29,87,93-94`

## Validation
✅ PoC test passes  
✅ Manual review confirmed  
✅ Logic flaw verified

---

**XP Expected:** 100 XP (High severity)
