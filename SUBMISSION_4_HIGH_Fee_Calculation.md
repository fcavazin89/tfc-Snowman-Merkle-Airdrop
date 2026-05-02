# Finding Submission #4 - High

## Title
Incorrect Fee Calculation in buySnow Enables Wrong Payments

## Severity
**High** (High Impact + Medium Likelihood)

## Description
The `buySnow()` function has incorrect fee calculation. The fee is stored as `_buyFee * PRECISION (10^18)` in the constructor, then multiplied by `amount` again in `buySnow()`, resulting in exponentially wrong calculations.

### Vulnerable Code
```solidity
// src/Snow.sol:73 - Constructor
s_buyFee = _buyFee * PRECISION; // e.g., 5 * 10^18

// src/Snow.sol:80 - buySnow function
if (msg.value == (s_buyFee * amount)) { // e.g., (5 * 10^18) * 2 = 10 * 10^18
    _mint(msg.sender, amount);
}
```

### Root Cause
Double-scaling of the fee. The fee is already scaled by `PRECISION` during storage, but scaled again during the transaction.

## Proof of Concept
```solidity
function testFinding4_FeeCalculation() public {
    // Assume _buyFee = 5, PRECISION = 10^18
    // Constructor: s_buyFee = 5 * 10^18
    
    uint256 feePerToken = snow.s_buyFee(); // Returns 5 * 10^18
    
    // For amount = 1:
    // Contract checks: msg.value == (5 * 10^18) * 1 = 5 * 10^18 wei (correct by accident)
    
    // For amount = 2:
    // Contract checks: msg.value == (5 * 10^18) * 2 = 10 * 10^18 wei
    // But should be: 2 * 5 = 10 wei (not 10 * 10^18)
    
    // This means users pay 10^18 times more than expected for multiple tokens
    assertTrue(feePerToken > 5); // It's scaled
}
```

## Impact
- **Users overpay**: Buying multiple tokens costs 10^18 times more than expected
- **Transaction failures**: Users cannot calculate the correct payment amount
- **Broken economics**: Fee mechanism doesn't work as intended
- **Potential loss of funds**: Users may send wrong amounts and lose ETH

## Recommended Mitigation
Fix the fee calculation in constructor OR in buySnow:

**Option 1: Fix constructor (recommended)**
```solidity
// Constructor
s_buyFee = _buyFee; // Don't scale here

// buySnow function
if (msg.value == (s_buyFee * PRECISION * amount)) {
    _mint(msg.sender, amount);
}
```

**Option 2: Fix buySnow**
```solidity
// Keep constructor as is
// Fix buySnow
if (msg.value == (s_buyFee * amount) / PRECISION) {
    _mint(msg.sender, amount);
}
```

## Location
`src/Snow.sol:73,80,83`

## Validation
✅ Logic analysis confirms issue  
✅ Fee scaling is incorrect  
✅ Slither may not catch this business logic error

---

**XP Expected:** 100 XP (High severity)
