// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract TicketingContract is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant USER_ROLE = keccak256("USER_ROLE");

    constructor() {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function grantUserRole(address account) public onlyRole(ADMIN_ROLE) {
        _grantRole(USER_ROLE, account);
    }

    function revokeUserRole(address account) public onlyRole(ADMIN_ROLE) {
        _revokeRole(USER_ROLE, account);
    }

    function isUser(address account) public view returns (bool) {
        return hasRole(USER_ROLE, account);
    }
}