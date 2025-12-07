pragma solidity ^0.8.30;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ticket} from "./Ticket.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract arenaMarketPlace is AccessControl, ReentrancyGuard, Pausable, IERC2981 {
    bytes32 public constant LISTER_ROLE = keccak256("LISTER_ROLE");
    address public ticket;
       struct Ticket {
        uint256 tokenId;
        uint256 price;
        address seller;
        bool listed;
    }
    mapping(uint256 => Ticket) public tickets;
    mapping(address => uint256) public maxResalePrice;
    uint256 public feeBps;
    address public treasury;

    IERC721 public ticketContract;

    event TicketListed(uint256 indexed tokenId, uint256 price, address indexed seller);
    event TicketUnlisted(uint256 indexed tokenId, address indexed seller);
    event TicketBought(uint256 indexed tokenId, address indexed buyer, uint256 price);


    constructor(address _ticket) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LISTER_ROLE, msg.sender);
        ticket = _ticket;
    }
 
    function listTicket(uint256 tokenId, uint256 price) external {
        // validation logic
        require(ticketContract.ownerOf(tokenId) == msg.sender, "Not owner");
        
        // transfer nft -> marketplace
        ticketContract.transferFrom(msg.sender, address(this), tokenId);

        tickets[tokenId] = Ticket(tokenId, msg.sender, price, true);
        emit TicketListed(tokenId, price);
    }


    function unlistTicket(uint256 tokenId) external {
        // validation logic
        require(tickets[tokenId].seller == msg.sender, "Not seller");
        require(tickets[tokenId].listed, "Not listed");
        // transfer nft -> seller
        ticketContract.transferFrom(address(this), msg.sender, tokenId);
        tickets[tokenId].listed = false;
        emit TicketUnlisted(tokenId, msg.sender);
    }

//    function buyTicket(uint256 tokenId) external onlyRole(LISTER_ROLE) returns (bool) {
    function buyTicket(uint256 tokenId) external payable nonReentrant {
        Listing memory item = listings[tokenId];
        require(item.active, "Not for sale");
        require(msg.value >= item.price, "Insufficient funds");

        // Calculate fees
        uint256 fee = (item.price * feeBps) / 10000;
        uint256 sellerAmount = item.price - fee;

        // Effects
        listings[tokenId].active = false;

        // Interactions
        (bool success1, ) = treasury.call{value: fee}("");
        require(success1, "Fee transfer failed");
        
        (bool success2, ) = item.seller.call{value: sellerAmount}("");
        require(success2, "Seller transfer failed");

        ticketContract.transferFrom(address(this), msg.sender, tokenId);
        
        emit TicketSold(tokenId, msg.sender, item.price);
}


