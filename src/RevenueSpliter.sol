// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title ArenaRevenueSplitter
 * @notice Immutable revenue splitter with ETH and ERC20 release.
 *         Anyone can call release functions; owner-only helpers allow batching.
 */
contract ArenaRevenueSplitter is Ownable {
    // Immutable payee/share config
    uint256 private _totalShares;
    uint256 private _totalReleased;

    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _released;
    address[] private _payees;




    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    event PaymentReceived(address from, uint256 amount);

 
    constructor(address[] memory payees, uint256[] memory shares_) Ownable(msg.sender) {
        require(payees.length == shares_.length, "Splitter: length mismatch");
        require(payees.length > 0, "Splitter: no payees");

        for (uint256 i = 0; i < payees.length; i++) {
            _addPayee(payees[i], shares_[i]);
        }
    }


    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }


    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    function totalReleased() external view returns (uint256) {
        return _totalReleased;
    }

    function shares(address account) external view returns (uint256) {
        return _shares[account];
    }

    function released(address account) external view returns (uint256) {
        return _released[account];
    }

    function payee(uint256 index) external view returns (address) {
        return _payees[index];
    }

    function releasable(address account) public view returns (uint256) {
        uint256 totalReceived = address(this).balance + _totalReleased;
        return _pendingPayment(account, totalReceived, _released[account]);
    }


    function release() external {
        address payable account = payable(msg.sender);
        require(_shares[account] > 0, "Splitter: no shares");

        uint256 payment = releasable(account);
        require(payment != 0, "Splitter: nothing due");

        _released[account] += payment;
        _totalReleased += payment;

        (bool ok, ) = account.call{value: payment}("");
        require(ok, "Splitter: ETH transfer failed");

        emit PaymentReleased(account, payment);
    }



    function _addPayee(address account, uint256 shares_) internal {
        require(account != address(0), "Splitter: zero account");
        require(shares_ > 0, "Splitter: zero shares");
        require(_shares[account] == 0, "Splitter: duplicate payee");

        _payees.push(account);
        _shares[account] = shares_;
        _totalShares += shares_;

        emit PayeeAdded(account, shares_);
    }

    function _pendingPayment(address account, uint256 totalReceived, uint256 alreadyReleased)
        internal
        view
        returns (uint256)
    {
        return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
    }
}
