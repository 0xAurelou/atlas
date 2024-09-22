// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface IFlashLoanReceiver {
    function executeOperation(uint256 amount, uint256 fee, bytes calldata params) external returns (bool);
}

contract PointsVaultWithETHRewards is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable pointsToken;
    uint256 public constant FLASH_LOAN_FEE = 9; // 0.09% fee
    uint256 public constant FLASH_LOAN_FEE_DENOMINATOR = 10_000;
    bytes32 public constant FLASHLOAN_ROLE = keccak256("FLASHLOAN_ROLE");

    uint256 public totalFees;
    bytes32 public feeMerkleRoot;
    mapping(address => uint256) public claimedFees;
    mapping(address => uint256) public balances;
    mapping(address => bool) public hasFlashloanRole;
    uint256 public totalSupply;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);
    event FeesDistributed(bytes32 merkleRoot, uint256 totalDistributed);
    event FeeClaimed(address indexed user, uint256 amount);
    event FlashloanRoleAdded(address indexed account);
    event ETHReceived(uint256 amount);

    // Custom errors
    error ZeroAmount();
    error InsufficientBalance();
    error FlashLoanExecutionFailed();
    error InvalidMerkleProof();
    error FeeAlreadyClaimed();
    error NoFeesToDistribute();
    error NotAuthorized();
    error FlashLoanTaken(address receiver, uint256 amount);
    error FlashLoanReturned(address receiver, uint256 amount);

    constructor(address _pointsToken) {
        pointsToken = IERC20(_pointsToken);
    }

    modifier onlyFlashloan() {
        if (!hasFlashloanRole[msg.sender]) revert NotAuthorized();
        _;
    }

    function addFlashloanRole(address account) external onlyOwner {
        hasFlashloanRole[account] = true;
        emit FlashloanRoleAdded(account);
    }

    function deposit(uint256 amount) public nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        pointsToken.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        totalSupply += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        balances[msg.sender] -= amount;
        totalSupply -= amount;
        pointsToken.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function flashLoan(address receiver, uint256 amount) external nonReentrant whenNotPaused onlyFlashloan {
        if (pointsToken.balanceOf(address(this)) < amount) revert InsufficientBalance();
        uint256 fee = (amount * FLASH_LOAN_FEE) / FLASH_LOAN_FEE_DENOMINATOR;

        // Transfer the amount to the receiver
        pointsToken.safeTransfer(receiver, amount);
        emit FlashLoanTaken(receiver, amount);

        // Execute the flash loan operation
        if (!IFlashLoanReceiver(receiver).executeOperation(amount, fee, "")) {
            revert FlashLoanExecutionFailed();
        }

        // Check if the loan plus fee has been returned
        if (pointsToken.balanceOf(address(this)) < totalSupply + fee) {
            revert FlashLoanExecutionFailed();
        }

        totalFees += fee;
        emit FlashLoan(receiver, amount, fee);
    }

    function totalAssets() public view returns (uint256) {
        return pointsToken.balanceOf(address(this));
    }

    function setFeeMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        feeMerkleRoot = _merkleRoot;
        emit FeesDistributed(_merkleRoot, totalFees);
        totalFees = 0;
    }

    function claimFees(uint256 amount, bytes32[] calldata merkleProof) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (claimedFees[msg.sender] >= amount) revert FeeAlreadyClaimed();
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!MerkleProof.verify(merkleProof, feeMerkleRoot, leaf)) revert InvalidMerkleProof();
        uint256 claimableAmount = amount - claimedFees[msg.sender];
        claimedFees[msg.sender] = amount;
        payable(msg.sender).transfer(claimableAmount);
        emit FeeClaimed(msg.sender, claimableAmount);
    }

    // Emergency functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Placeholder for onlyOwner modifier
    modifier onlyOwner() {
        if (msg.sender != ATLAS) revert NotAuthorized();
        _;
    }

    // Placeholder for ATLAS address
    address private constant ATLAS = address(0); // Replace with actual ATLAS address

    receive() external payable {
        emit ETHReceived(msg.value);
    }
}
