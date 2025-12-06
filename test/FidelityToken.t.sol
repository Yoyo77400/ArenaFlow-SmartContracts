// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FidelityToken} from "../src/FidelityToken.sol";

contract FidelityTokenTest is Test {
    FidelityToken public token;

    address public admin = address(1);
    address public minter = address(2);
    address public user = address(3);
    address public spender = address(4);

    uint256 public userPrivateKey = 0x1234;
    address public userWithKey;

    function setUp() public {
        userWithKey = vm.addr(userPrivateKey);

        vm.startPrank(admin);
        token = new FidelityToken("Fidelity Points", "FID");
        // Grant minter role
        token.grantRole(token.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // =====================================================
    // Basic ERC20 Tests
    // =====================================================

    function test_Name() public view {
        assertEq(token.name(), "Fidelity Points");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "FID");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), 1000000 * 10 ** 18);
        assertEq(token.balanceOf(admin), 1000000 * 10 ** 18);
    }

    // =====================================================
    // Minting Tests
    // =====================================================

    function test_Mint_AsMinter() public {
        vm.prank(minter);
        token.mint(user, 1000);
        assertEq(token.balanceOf(user), 1000);
    }

    function test_Mint_RevertsForNonMinter() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1000);
    }

    // =====================================================
    // Burning Tests (ERC20Burnable)
    // =====================================================

    function test_Burn() public {
        // Transfer some tokens to user first
        vm.prank(admin);
        token.transfer(user, 1000);

        // User burns their tokens
        vm.prank(user);
        token.burn(500);

        assertEq(token.balanceOf(user), 500);
    }

    function test_BurnFrom() public {
        // Transfer tokens and approve
        vm.prank(admin);
        token.transfer(user, 1000);

        vm.prank(user);
        token.approve(spender, 500);

        // Spender burns from user
        vm.prank(spender);
        token.burnFrom(user, 500);

        assertEq(token.balanceOf(user), 500);
    }

    // =====================================================
    // ERC20Permit Tests
    // =====================================================

    function test_SupportsERC20PermitInterface() public view {
        // Check DOMAIN_SEPARATOR is accessible (EIP-2612)
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0));
    }

    function test_Nonces_StartsAtZero() public view {
        assertEq(token.nonces(userWithKey), 0);
    }

    function test_Permit_AllowsGaslessApproval() public {
        // Give user some tokens
        vm.prank(minter);
        token.mint(userWithKey, 1000);

        uint256 amount = 500;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(userWithKey);

        // Create permit signature
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                userWithKey,
                spender,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Anyone can submit the permit (gasless for the user)
        vm.prank(spender);
        token.permit(userWithKey, spender, amount, deadline, v, r, s);

        // Check allowance was set
        assertEq(token.allowance(userWithKey, spender), amount);
        // Check nonce was incremented
        assertEq(token.nonces(userWithKey), 1);
    }

    function test_Permit_RevertsWithExpiredDeadline() public {
        vm.prank(minter);
        token.mint(userWithKey, 1000);

        uint256 amount = 500;
        uint256 deadline = block.timestamp - 1; // Expired
        uint256 nonce = token.nonces(userWithKey);

        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                userWithKey,
                spender,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert();
        token.permit(userWithKey, spender, amount, deadline, v, r, s);
    }

    function test_Permit_RevertsWithInvalidSignature() public {
        vm.prank(minter);
        token.mint(userWithKey, 1000);

        uint256 amount = 500;
        uint256 deadline = block.timestamp + 1 hours;

        // Use wrong private key
        uint256 wrongKey = 0x9999;
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                userWithKey,
                spender,
                amount,
                0,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);

        vm.expectRevert();
        token.permit(userWithKey, spender, amount, deadline, v, r, s);
    }

    function test_Permit_RevertsWithReusedNonce() public {
        vm.prank(minter);
        token.mint(userWithKey, 1000);

        uint256 amount = 500;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(userWithKey);

        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                userWithKey,
                spender,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // First permit works
        token.permit(userWithKey, spender, amount, deadline, v, r, s);

        // Replay should fail
        vm.expectRevert();
        token.permit(userWithKey, spender, amount, deadline, v, r, s);
    }

    // =====================================================
    // Access Control Tests
    // =====================================================

    function test_AdminCanGrantMinterRole() public {
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), user);
        vm.stopPrank();
        assertTrue(token.hasRole(token.MINTER_ROLE(), user));
    }

    function test_NonAdminCannotGrantRoles() public {
        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(user);
        vm.expectRevert();
        token.grantRole(minterRole, user);
    }
}
