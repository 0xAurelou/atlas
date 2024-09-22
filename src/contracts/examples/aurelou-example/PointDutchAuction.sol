// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DutchAuctionForPoints {
    IERC20 public paymentToken;
    address public lendingContract;

    uint256 public startPrice;
    uint256 public endPrice;
    uint256 public auctionDuration;
    uint256 public startTime;
    uint256 public pointsForSale;

    bool public auctionEnded;

    event AuctionStarted(uint256 startPrice, uint256 endPrice, uint256 duration);
    event PointsPurchased(address buyer, uint256 amount, uint256 price);
    event AuctionEnded(uint256 finalPrice);

    // Custom errors
    error AuctionAlreadyEnded();
    error InvalidPricing();
    error InvalidDuration();
    error AuctionNotStarted();
    error InvalidAmount();
    error InsufficientPointsAvailable();
    error PaymentTransferFailed();
    error AuctionCannotBeEndedYet();

    constructor(address _paymentToken, address _lendingContract) {
        paymentToken = IERC20(_paymentToken);
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

    function buyPoints(uint256 amount) external {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (amount == 0) revert InvalidAmount();
        if (amount > pointsForSale) revert InsufficientPointsAvailable();

        uint256 price = getCurrentPrice();
        uint256 totalCost = price * amount;

        if (!paymentToken.transferFrom(msg.sender, address(this), totalCost)) revert PaymentTransferFailed();

        // Transfer points to the buyer (implement this in the LendingWithPoints contract)
        // LendingWithPoints(lendingContract).transferPoints(msg.sender, amount);

        pointsForSale -= amount;

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
}
