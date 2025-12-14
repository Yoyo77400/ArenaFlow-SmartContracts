// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    ERC2771Context
} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import {FidelityToken} from "./FidelityToken.sol";

contract Ticket is
    ERC721,
    ERC2981,
    AccessControl,
    Pausable,
    ReentrancyGuard,
    ERC2771Context
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 private _tokenIdCounter;

    address public revenueSplitter;
    uint256 public ticketPriceWei;

    // Capacity limit (0 = unlimited)
    uint256 public maxSupply;
    uint256 public totalSupply;

    // Metadata
    string private _baseTokenURI;

    FidelityToken public loyaltyToken;
    uint256 public loyaltyRewardPerPurchase;

    event TicketBought(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 pricePaid,
        address paymentToken
    );

    event MaxSupplyUpdated(uint256 oldMaxSupply, uint256 newMaxSupply);
    event BaseURIUpdated(string newBaseURI);

    error SoldOut();
    error InsufficientETH();
    error SplitterNotSet();
    error RefundFailed();
    error TicketPriceNotSet();
    error InvalidSplitter();
    error MaxSupplyBelowCurrent();
    error SpliterTransferFailed();

    constructor(
        string memory name_,
        string memory symbol_,
        address trustedForwarder
    ) ERC721(name_, symbol_) ERC2771Context(trustedForwarder) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        revenueSplitter = address(0);
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(Context, ERC2771Context)
        returns (uint256)
    {
        return ERC2771Context._contextSuffixLength();
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _msgSender()
        internal
        view
        virtual
        override(Context, ERC2771Context)
        returns (address sender)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
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
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override whenNotPaused {
        super._increaseBalance(account, value);
    }

    // Admin config
    function setRevenueSplitter(address newSplitter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSplitter != address(0), InvalidSplitter());
        revenueSplitter = newSplitter;
    }

    function setTicketPriceWei(
        uint256 newPriceWei
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ticketPriceWei = newPriceWei;
    }

    function setLoyaltyConfig(
        address token,
        uint256 rewardAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        loyaltyToken = FidelityToken(token);
        loyaltyRewardPerPurchase = rewardAmount;
    }

    // Capacity configuration
    function setMaxSupply(
        uint256 newMaxSupply
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            newMaxSupply == 0 || newMaxSupply >= totalSupply,
            MaxSupplyBelowCurrent()
        );
        uint256 oldMaxSupply = maxSupply;
        maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(oldMaxSupply, newMaxSupply);
    }

    // Metadata configuration
    function setBaseURI(
        string calldata newBaseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(
                    abi.encodePacked(
                        baseURI,
                        Strings.toString(tokenId),
                        ".json"
                    )
                )
                : "";
    }

    function remainingSupply() public view returns (uint256) {
        if (maxSupply == 0) return type(uint256).max;
        return maxSupply - totalSupply;
    }

    // Royalty configuration (ERC-2981)
    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _deleteDefaultRoyalty();
    }

    function resetTokenRoyalty(
        uint256 tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _resetTokenRoyalty(tokenId);
    }

    // Achat avec ETH
    function buyTicket()
        external
        payable
        nonReentrant
        returns (uint256 tokenId)
    {
        require(ticketPriceWei > 0, TicketPriceNotSet());
        require(msg.value >= ticketPriceWei, InsufficientETH());
        require(maxSupply == 0 || totalSupply < maxSupply, SoldOut());
        require(revenueSplitter != address(0), SplitterNotSet());

        unchecked {
            _tokenIdCounter += 1;
            totalSupply += 1;
        }
        tokenId = _tokenIdCounter;

        _safeMint(msg.sender, tokenId);

        // Forward ETH to revenue splitter
        (bool ok, ) = payable(revenueSplitter).call{value: ticketPriceWei}("");
        require(ok, SpliterTransferFailed());

        // Refund excess ETH if any
        uint256 excess = msg.value - ticketPriceWei;
        if (excess > 0) {
            (ok, ) = payable(msg.sender).call{value: excess}("");
            require(ok, RefundFailed());
        }

        // Mint loyalty rewards (requires this contract to own FidelityToken)
        if (
            address(loyaltyToken) != address(0) && loyaltyRewardPerPurchase > 0
        ) {
            loyaltyToken.mint(msg.sender, loyaltyRewardPerPurchase);
        }

        emit TicketBought(msg.sender, tokenId, ticketPriceWei, address(0));
    }

    // Accept ETH if sent directly
    receive() external payable {}
}
