// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Ticket.sol";
import "./FidelityToken.sol";

contract TicketingFactory {
    address[] public events;

    event EventCreated(address indexed organizer, address ticket, string name, string symbol, uint256 price);
    event LoyaltyConfigSet(address indexed ticket, address indexed loyaltyToken, uint256 rewardAmount);
    event LoyaltyMinterGrantAttempt(address indexed loyaltyToken, address indexed ticket, bool success);

    function createEvent(string memory name, string memory symbol, uint256 price, address loyaltyToken, uint256 rewardAmount, address trustedForwarder) external returns (address ticketAddress) {
        Ticket ticket = new Ticket(name, symbol, trustedForwarder);

        // Configure event with initial parameters while factory still has admin role
        ticket.setTicketPriceWei(price);
        ticket.setTreasury(payable(msg.sender));

        // Give organizer pauser powers and remove factory
        bytes32 pauserRole = ticket.PAUSER_ROLE();
        ticket.grantRole(pauserRole, msg.sender);
        ticket.revokeRole(pauserRole, address(this));

        // Optional loyalty setup
        if (loyaltyToken != address(0) && rewardAmount > 0) {
            ticket.setLoyaltyConfig(loyaltyToken, rewardAmount);
            emit LoyaltyConfigSet(address(ticket), loyaltyToken, rewardAmount);

            // Attempt to grant MINTER_ROLE on the loyalty token to the ticket.
            // This will succeed only if the factory has the admin role on the token.
            FidelityToken token = FidelityToken(loyaltyToken);
            bool success = false;
            try token.grantRole(token.MINTER_ROLE(), address(ticket)) {
                success = true;
            } catch {}
            emit LoyaltyMinterGrantAttempt(loyaltyToken, address(ticket), success);
        }

        // Transfer admin to organizer and revoke from factory
        bytes32 adminRole = ticket.DEFAULT_ADMIN_ROLE();
        ticket.grantRole(adminRole, msg.sender);
        ticket.revokeRole(adminRole, address(this));

        // Registry
        ticketAddress = address(ticket);
        events.push(ticketAddress);

        emit EventCreated(msg.sender, ticketAddress, name, symbol, price);
    }

    function getAllEvents() external view returns (address[] memory) {
        return events;
    }
}
