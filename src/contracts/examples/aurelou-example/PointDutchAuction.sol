// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DutchAuctionForPoints is ReentrancyGuard {
    IERC20 public pointsToken;
    address public lendingContract;
    uint256 public startPrice;
    uint256 public endPrice;
    uint256 public auctionDuration;
    uint256 public startTime;
    uint256 public pointsForSale;
    bool public auctionEnded;

    mapping(address => uint256) public userPointsBalance;

    event AuctionStarted(uint256 startPrice, uint256 endPrice, uint256 duration);
    event PointsPurchased(address buyer, uint256 amount, uint256 price);
    event AuctionEnded(uint256 finalPrice);
    event PointDeposit(address indexed from, uint256 amount);
    event PointWithdrawal(address indexed to, uint256 amount);

    // Custom errors
    error AuctionAlreadyEnded();
    error InvalidPricing();
    error InvalidDuration();
    error AuctionNotStarted();
    error InvalidAmount();
    error InsufficientPointsAvailable();
    error InsufficientPayment();
    error AuctionCannotBeEndedYet();
    error TransferFailed();

    constructor(address _pointsToken, address _lendingContract) {
        pointsToken = IERC20(_pointsToken);
        lendingContract = _lendingContract;
    }

    function startAuction(uint256 _startPrice, uint256 _endPrice, uint256 _duration, uint256 _pointsForSale) external {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (_startPrice <= _endPrice) revert InvalidPricing();
        if (_duration == 0) revert InvalidDuration();

        startPrice = _startPrice;
        endPrice = _endPrice;
        auctionDuration = _duration;
        startTime = block.timestamp;
        pointsForSale = _pointsForSale;

        emit AuctionStarted(startPrice, endPrice, auctionDuration);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (startTime == 0) revert AuctionNotStarted();
        if (block.timestamp >= startTime + auctionDuration) {
            return endPrice;
        }
        uint256 elapsed = block.timestamp - startTime;
        uint256 priceDrop = ((startPrice - endPrice) * elapsed) / auctionDuration;
        return startPrice - priceDrop;
    }

    function buyPoints(uint256 amount) external payable nonReentrant {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (amount == 0) revert InvalidAmount();
        if (amount > pointsForSale) revert InsufficientPointsAvailable();

        uint256 price = getCurrentPrice();
        uint256 totalCost = price * amount;

        if (msg.value < totalCost) revert InsufficientPayment();

        pointsForSale -= amount;
        userPointsBalance[msg.sender] += amount;

        // Refund excess ETH
        if (msg.value > totalCost) {
            (bool success,) = payable(msg.sender).call{ value: msg.value - totalCost }("");
            if (!success) revert TransferFailed();
        }

        emit PointsPurchased(msg.sender, amount, price);

        if (pointsForSale == 0) {
            endAuction();
        }
    }

    function endAuction() public {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (block.timestamp < startTime + auctionDuration && pointsForSale > 0) revert AuctionCannotBeEndedYet();

        auctionEnded = true;
        emit AuctionEnded(getCurrentPrice());
    }

    function depositPoints(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (!pointsToken.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        userPointsBalance[msg.sender] += amount;
        emit PointDeposit(msg.sender, amount);
    }

    function withdrawPoints(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (userPointsBalance[msg.sender] < amount) revert InsufficientPointsAvailable();

        userPointsBalance[msg.sender] -= amount;
        if (!pointsToken.transfer(msg.sender, amount)) revert TransferFailed();

        emit PointWithdrawal(msg.sender, amount);
    }

    receive() external payable { }

    fallback() external payable { }
}
