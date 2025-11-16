// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; 

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Ticket } from "./Ticket.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TicketValidator is AccessControl, EIP712, IERC1271 {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 private constant _TYPEHASH = keccak256("Ticket(address to,uint256 tokenId)");

    constructor() EIP712("TicketingSystem", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function hashTicket(address to, uint256 tokenId) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(_TYPEHASH, to, tokenId)));
    }

    function verifySignature(address to, uint256 tokenId, bytes memory signature) public view returns (bool) {
        bytes32 digest = hashTicket(to, tokenId);
        address signer = ECDSA.recover(digest, signature);
        return hasRole(VALIDATOR_ROLE, signer);
    }

    /** 
     * @dev See {IERC1271-isValidSignature}.
     *returns (bytes4) 0x1626ba7e if the signature is valid, otherwise returns 0xffffffff.
    */
    function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (hasRole(VALIDATOR_ROLE, signer)) {
            return 0x1626ba7e;
        } else {
            return 0xffffffff;
        }
    }
}