// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Ticket} from "../src/Ticket.sol";
import {TicketingFactory} from "../src/TicketingFactory.sol";
import {FidelityToken} from "../src/FidelityToken.sol";

contract TicketTest is Test {
    Ticket public ticket;
    TicketingFactory public factory;
    FidelityToken public loyaltyToken;

    address public admin = address(1);
    address public organizer = address(2);
    address public buyer = address(3);
    address public royaltyReceiver = address(4);
    address public trustedForwarder = address(5);

    uint256 public constant TICKET_PRICE = 0.1 ether;
    uint96 public constant DEFAULT_ROYALTY = 500; // 5%

    function setUp() public {
        vm.startPrank(admin);

        // Deploy factory
        factory = new TicketingFactory();

        // Deploy loyalty token
        loyaltyToken = new FidelityToken("Loyalty", "LOY");

        vm.stopPrank();

        // Create an event as organizer
        vm.startPrank(organizer);
        address ticketAddress = factory.createEvent(
            "Test Event",
            "TEST",
            TICKET_PRICE,
            0, // No max supply (unlimited)
            "", // No baseURI
            address(0), // No loyalty token
            0,
            trustedForwarder,
            DEFAULT_ROYALTY
        );
        ticket = Ticket(ticketAddress);
        vm.stopPrank();
    }

    // =====================================================
    // ERC-2981 Interface Support Tests
    // =====================================================

    function test_SupportsERC2981Interface() public view {
        // ERC-2981 interface ID = 0x2a55205a
        bytes4 erc2981InterfaceId = 0x2a55205a;
        assertTrue(ticket.supportsInterface(erc2981InterfaceId));
    }

    function test_SupportsERC721Interface() public view {
        // ERC-721 interface ID = 0x80ac58cd
        bytes4 erc721InterfaceId = 0x80ac58cd;
        assertTrue(ticket.supportsInterface(erc721InterfaceId));
    }

    function test_SupportsAccessControlInterface() public view {
        // AccessControl interface ID = 0x7965db0b
        bytes4 accessControlInterfaceId = 0x7965db0b;
        assertTrue(ticket.supportsInterface(accessControlInterfaceId));
    }

    // =====================================================
    // Default Royalty Tests
    // =====================================================

    function test_DefaultRoyaltyIsSetOnCreation() public {
        // Buy a ticket first
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        // Check royalty info
        uint256 salePrice = 1 ether;
        (address receiver, uint256 royaltyAmount) = ticket.royaltyInfo(
            tokenId,
            salePrice
        );

        // Organizer should receive royalties (same as treasury)
        assertEq(receiver, organizer);
        // 5% of 1 ether = 0.05 ether
        assertEq(royaltyAmount, 0.05 ether);
    }

    function test_RoyaltyCalculation_Precise() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        // Test with various sale prices
        uint256 salePrice1 = 1 ether;
        (, uint256 royalty1) = ticket.royaltyInfo(tokenId, salePrice1);
        assertEq(royalty1, 0.05 ether); // 5% of 1 ETH

        uint256 salePrice2 = 10 ether;
        (, uint256 royalty2) = ticket.royaltyInfo(tokenId, salePrice2);
        assertEq(royalty2, 0.5 ether); // 5% of 10 ETH

        uint256 salePrice3 = 0.5 ether;
        (, uint256 royalty3) = ticket.royaltyInfo(tokenId, salePrice3);
        assertEq(royalty3, 0.025 ether); // 5% of 0.5 ETH
    }

    function test_SetDefaultRoyalty_AsAdmin() public {
        // Organizer is admin
        vm.prank(organizer);
        ticket.setDefaultRoyalty(royaltyReceiver, 1000); // 10%

        // Buy a ticket
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        // Check new royalty
        (address receiver, uint256 royaltyAmount) = ticket.royaltyInfo(
            tokenId,
            1 ether
        );
        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, 0.1 ether); // 10%
    }

    function test_SetDefaultRoyalty_RevertsForNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        ticket.setDefaultRoyalty(royaltyReceiver, 1000);
    }

    function test_DeleteDefaultRoyalty() public {
        vm.prank(organizer);
        ticket.deleteDefaultRoyalty();

        // Buy a ticket
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        // Check royalty is zero
        (address receiver, uint256 royaltyAmount) = ticket.royaltyInfo(
            tokenId,
            1 ether
        );
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_DeleteDefaultRoyalty_RevertsForNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        ticket.deleteDefaultRoyalty();
    }

    // =====================================================
    // Per-Token Royalty Tests
    // =====================================================

    function test_SetTokenRoyalty_OverridesDefault() public {
        // Buy tickets
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        uint256 tokenId1 = ticket.buyTicket{value: TICKET_PRICE}();
        uint256 tokenId2 = ticket.buyTicket{value: TICKET_PRICE}();
        vm.stopPrank();

        // Set specific royalty for token 1
        vm.prank(organizer);
        ticket.setTokenRoyalty(tokenId1, royaltyReceiver, 2000); // 20%

        // Token 1 should have 20% royalty
        (address receiver1, uint256 royalty1) = ticket.royaltyInfo(
            tokenId1,
            1 ether
        );
        assertEq(receiver1, royaltyReceiver);
        assertEq(royalty1, 0.2 ether);

        // Token 2 should still have default 5% royalty
        (address receiver2, uint256 royalty2) = ticket.royaltyInfo(
            tokenId2,
            1 ether
        );
        assertEq(receiver2, organizer);
        assertEq(royalty2, 0.05 ether);
    }

    function test_SetTokenRoyalty_RevertsForNonAdmin() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        vm.prank(buyer);
        vm.expectRevert();
        ticket.setTokenRoyalty(tokenId, royaltyReceiver, 1000);
    }

    function test_ResetTokenRoyalty() public {
        // Buy a ticket
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        // Set token-specific royalty
        vm.prank(organizer);
        ticket.setTokenRoyalty(tokenId, royaltyReceiver, 2000); // 20%

        // Verify it's set
        (, uint256 royaltyBefore) = ticket.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyBefore, 0.2 ether);

        // Reset to default
        vm.prank(organizer);
        ticket.resetTokenRoyalty(tokenId);

        // Should be back to default 5%
        (address receiver, uint256 royaltyAfter) = ticket.royaltyInfo(
            tokenId,
            1 ether
        );
        assertEq(receiver, organizer);
        assertEq(royaltyAfter, 0.05 ether);
    }

    function test_ResetTokenRoyalty_RevertsForNonAdmin() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        vm.prank(buyer);
        vm.expectRevert();
        ticket.resetTokenRoyalty(tokenId);
    }

    // =====================================================
    // Factory Royalty Tests
    // =====================================================

    function test_FactoryCreatesEventWithDefaultRoyalty() public {
        vm.prank(organizer);
        address newTicketAddr = factory.createEvent(
            "New Event",
            "NEW",
            TICKET_PRICE,
            0, // unlimited
            "",
            address(0),
            0,
            trustedForwarder,
            0 // Should default to 500 (5%)
        );

        Ticket newTicket = Ticket(newTicketAddr);

        // Buy a ticket
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = newTicket.buyTicket{value: TICKET_PRICE}();

        // Check royalty is 5%
        (, uint256 royaltyAmount) = newTicket.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyAmount, 0.05 ether);
    }

    function test_FactoryCreatesEventWithCustomRoyalty() public {
        vm.prank(organizer);
        address newTicketAddr = factory.createEvent(
            "VIP Event",
            "VIP",
            TICKET_PRICE,
            0,
            "",
            address(0),
            0,
            trustedForwarder,
            1000 // 10%
        );

        Ticket newTicket = Ticket(newTicketAddr);

        // Buy a ticket
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = newTicket.buyTicket{value: TICKET_PRICE}();

        // Check royalty is 10%
        (, uint256 royaltyAmount) = newTicket.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyAmount, 0.1 ether);
    }

    // =====================================================
    // Edge Cases
    // =====================================================

    function test_RoyaltyWithZeroSalePrice() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        (, uint256 royaltyAmount) = ticket.royaltyInfo(tokenId, 0);
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyWithMaxFee() public {
        // Set royalty to 100% (max allowed)
        vm.prank(organizer);
        ticket.setDefaultRoyalty(royaltyReceiver, 10000); // 100%

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        (, uint256 royaltyAmount) = ticket.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyAmount, 1 ether);
    }

    function test_RoyaltyExceedingMaxReverts() public {
        vm.prank(organizer);
        vm.expectRevert(); // ERC2981 reverts if fee > 10000
        ticket.setDefaultRoyalty(royaltyReceiver, 10001);
    }

    function test_SetRoyaltyToZeroAddress() public {
        vm.prank(organizer);
        vm.expectRevert(); // ERC2981 reverts for address(0)
        ticket.setDefaultRoyalty(address(0), 500);
    }

    // =====================================================
    // Max Supply / Capacity Limit Tests
    // =====================================================

    function test_SetMaxSupply() public {
        vm.prank(organizer);
        ticket.setMaxSupply(100);
        assertEq(ticket.maxSupply(), 100);
    }

    function test_SetMaxSupply_RevertsForNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        ticket.setMaxSupply(100);
    }

    function test_BuyTicket_RevertsWhenSoldOut() public {
        // Create event with max supply of 2
        vm.prank(organizer);
        address limitedAddr = factory.createEvent(
            "Limited Event",
            "LTD",
            TICKET_PRICE,
            2, // Only 2 tickets
            "",
            address(0),
            0,
            trustedForwarder,
            500
        );
        Ticket limitedTicket = Ticket(limitedAddr);

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);

        // Buy first 2 tickets
        limitedTicket.buyTicket{value: TICKET_PRICE}();
        limitedTicket.buyTicket{value: TICKET_PRICE}();

        // Third should revert
        vm.expectRevert("Sold out");
        limitedTicket.buyTicket{value: TICKET_PRICE}();

        vm.stopPrank();
    }

    function test_RemainingSupply() public {
        vm.prank(organizer);
        ticket.setMaxSupply(10);

        assertEq(ticket.remainingSupply(), 10);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        ticket.buyTicket{value: TICKET_PRICE}();

        assertEq(ticket.remainingSupply(), 9);
    }

    function test_RemainingSupply_UnlimitedReturnsMax() public {
        // No max supply set (unlimited)
        assertEq(ticket.remainingSupply(), type(uint256).max);
    }

    function test_TotalSupply_TracksCorrectly() public {
        assertEq(ticket.totalSupply(), 0);

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        ticket.buyTicket{value: TICKET_PRICE}();
        assertEq(ticket.totalSupply(), 1);

        ticket.buyTicket{value: TICKET_PRICE}();
        assertEq(ticket.totalSupply(), 2);
        vm.stopPrank();
    }

    function test_SetMaxSupply_RevertsBelowCurrentSupply() public {
        // Buy 3 tickets
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        ticket.buyTicket{value: TICKET_PRICE}();
        ticket.buyTicket{value: TICKET_PRICE}();
        ticket.buyTicket{value: TICKET_PRICE}();
        vm.stopPrank();

        // Try to set max supply below current
        vm.prank(organizer);
        vm.expectRevert("Max supply below current supply");
        ticket.setMaxSupply(2);
    }

    // =====================================================
    // Metadata / tokenURI Tests
    // =====================================================

    function test_SetBaseURI() public {
        vm.prank(organizer);
        ticket.setBaseURI("https://api.example.com/tickets/");

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        string memory uri = ticket.tokenURI(tokenId);
        assertEq(uri, "https://api.example.com/tickets/1.json");
    }

    function test_SetBaseURI_RevertsForNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        ticket.setBaseURI("https://api.example.com/");
    }

    function test_TokenURI_ReturnsEmptyWhenNoBaseURI() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = ticket.buyTicket{value: TICKET_PRICE}();

        string memory uri = ticket.tokenURI(tokenId);
        assertEq(uri, "");
    }

    function test_TokenURI_RevertsForNonExistentToken() public {
        vm.prank(organizer);
        ticket.setBaseURI("https://api.example.com/");

        vm.expectRevert();
        ticket.tokenURI(999);
    }

    function test_FactoryCreatesEventWithBaseURI() public {
        vm.prank(organizer);
        address newTicketAddr = factory.createEvent(
            "Metadata Event",
            "META",
            TICKET_PRICE,
            100,
            "https://metadata.example.com/event/",
            address(0),
            0,
            trustedForwarder,
            500
        );

        Ticket newTicket = Ticket(newTicketAddr);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokenId = newTicket.buyTicket{value: TICKET_PRICE}();

        assertEq(
            newTicket.tokenURI(tokenId),
            "https://metadata.example.com/event/1.json"
        );
    }
}
