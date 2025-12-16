// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;


import "forge-std/Script.sol";
import "../src/Ticket.sol";
import "../src/FidelityToken.sol";
import "../src/TicketingFactory.sol";
import "../src/TicketValidator.sol";
import "../src/RevenueSpliter.sol";
import "../src/ArenaMarketplace.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FidelityToken fidelityToken = new FidelityToken(string("FidelityToken"), string("FTK"));
        TicketingFactory ticketingFactory = new TicketingFactory();
        TicketValidator ticketValidator = new TicketValidator();

        address addressFidelityToken = address(fidelityToken);

        address ticketAddress = ticketingFactory.createEvent("test envent", "TST", 100, 1000, "ipfs:// baseURI", addressFidelityToken, 10, address(0), 500);
        Ticket ticket = Ticket(payable(ticketAddress));

        ArenaMarketPlace arenaMarketplace = new ArenaMarketPlace(addressFidelityToken);

        vm.stopBroadcast();
        console.log("Ticket deployed at:", address(ticket));
        console.log("TicketValidator deployed at:", address(ticketValidator));
        console.log("ArenaMarketplace deployed at:", address(arenaMarketplace));
        console.log("FidelityToken deployed at:", address(fidelityToken));
        console.log("TicketingFactory deployed at:", address(ticketingFactory));
    }
}