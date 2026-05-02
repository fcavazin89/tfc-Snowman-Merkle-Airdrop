# Finding Submission #5 - Medium

## Title
Unchecked ERC20 Transfer in collectFee

## Severity
**Medium** (Low Impact + High Likelihood)

## Description
The `collectFee()` function in `Snow.sol` uses `i_weth.transfer()` without checking the return value. Some ERC20 tokens don't revert on failure, which could lead to silent failures.

### Vulnerable Code
```solidity
// src/Snow.sol:101-102
uint256 collection = i_weth.balanceOf(address(this));
i_weth.transfer(s_collector, collection); // No return value check
```

### Root Cause
The contract uses `i_weth.transfer()` instead of `safeTransfer()` from OpenZeppelin's SafeERC20 library.

## Proof of Concept
```solidity
function testFinding5_UncheckedTransfer() public {
    // Setup: someone buys snow to get WETH into contract
    vm.startPrank(alice);
    weth.approve(address(snow), 5e18);
    snow.buySnow(1);
    vm.stopPrank();
    
    uint256 collectorBalanceBefore = weth.balanceOf(snow.getCollector());
    
    vm.prank(snow.getCollector());
    snow.collectFee();
    
    // Collector should receive WETH
    uint256 collectorBalanceAfter = weth.balanceOf(snow.getCollector());
    assertTrue(collectorBalanceAfter > collectorBalanceBefore);
}
```

## Impact
- **Silent failures**: If WETH transfer fails, the function won't revert
- **Fund loss**: Fees could be stuck in the contract permanently
- **False sense of security**: Contract appears to work but fees aren't collected

## Recommended Mitigation
Use SafeERC20's `safeTransfer()`:

```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// In collectFee():
function collectFee() external onlyCollector {
    uint256 collection = i_weth.balanceOf(address(this));
    i_weth.safeTransfer(s_collector, collection); // Now checks return value
    
    (bool collected,) = payable(s_collector).call{value: address(this).balance}("");
    require(collected, "Fee collection failed!!!");
}
```

## Location
`src/Snow.sol:101-103`

## Validation
✅ Slither detection: unchecked-transfer  
✅ Uses SafeERC20 for approve/transferFrom but not for transfer  
✅ OZ SafeERC20 already imported

---

**XP Expected:** 20 XP (Medium severity)
