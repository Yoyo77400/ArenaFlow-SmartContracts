// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ERC2771Context } from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import { FidelityToken } from "./FidelityToken.sol";

contract Ticket is ERC721, AccessControl, Pausable, ReentrancyGuard, ERC2771Context {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 private _tokenIdCounter;


    address payable public treasury;
    uint256 public ticketPriceWei;


    FidelityToken public loyaltyToken;
    uint256 public loyaltyRewardPerPurchase;

    event TicketBought(address indexed buyer, uint256 indexed tokenId, uint256 pricePaid, address paymentToken);

    constructor(string memory name_, string memory symbol_, address trustedForwarder) ERC721(name_, symbol_) ERC2771Context(trustedForwarder) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        treasury = payable(msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _msgSender() internal view override(Context, ERC2771Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    // Pause controls
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Block transfers/mints/burns while paused
    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override whenNotPaused {
        super._increaseBalance(account, value);
    }

    // Admin config
    function setTreasury(address payable newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury");
        treasury = newTreasury;
    }

    function setTicketPriceWei(uint256 newPriceWei) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ticketPriceWei = newPriceWei;
    }

    function setLoyaltyConfig(address token, uint256 rewardAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        loyaltyToken = FidelityToken(token);
        loyaltyRewardPerPurchase = rewardAmount;
    }

    // Achat avec ETH
    function buyTicket() external payable nonReentrant returns (uint256 tokenId) {
        require(ticketPriceWei > 0, "Price not set");
        require(msg.value >= ticketPriceWei, "Insufficient ETH sent");

        unchecked { _tokenIdCounter += 1; }
        tokenId = _tokenIdCounter;

        _safeMint(msg.sender, tokenId);

        // Forward ETH to treasury
        (bool ok, ) = treasury.call{ value: ticketPriceWei }("");
        require(ok, "Treasury transfer failed");

        // Refund excess ETH if any
        uint256 excess = msg.value - ticketPriceWei;
        if (excess > 0) {
            (ok, ) = payable(msg.sender).call{ value: excess }("");
            require(ok, "Refund failed");
        }

        // Mint loyalty rewards (requires this contract to own FidelityToken)
        if (address(loyaltyToken) != address(0) && loyaltyRewardPerPurchase > 0) {
            loyaltyToken.mint(msg.sender, loyaltyRewardPerPurchase);
        }

        emit TicketBought(msg.sender, tokenId, ticketPriceWei, address(0));
    }
}
