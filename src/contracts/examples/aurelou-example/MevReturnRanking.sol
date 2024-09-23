//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { DAppOperation } from "src/contracts/types/DAppOperation.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import { UserOperation } from "src/contracts/types/UserOperation.sol";
import { SolverOperation } from "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";

// Interface Import

import { IMevReturnRanking } from "src/contracts/examples/aurelou-example/interfaces/IMevReturnRanking.sol";
import { IPool } from "src/contracts/examples/aurelou-example/interfaces/IPool.sol";
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";
import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";

struct Approval {
    address token;
    address spender;
    uint256 amount;
}

struct Beneficiary {
    address owner;
    uint256 percentage; // out of 100
}

/*
* @title MevRefundRanking
* @notice This contract combines functionalities of V2RewardDAppControl and Ranking
* @dev This contract inherits from DAppControl and implements both reward and ranking systems
*/
contract MevRefundRanking is DAppControl {
    bytes32 constant SLOT = 0;
    address public immutable REWARD_TOKEN;
    address public immutable uniswapV2Router02;

    address private _userLock = address(1); // TODO: Convert to transient storage

    uint256 private constant _FEE_BASE = 100;
    uint256 public constant ONE_BPS_BASIS = 10_000;
    uint256 public constant ONE = 1e18;
    uint256 public constant ONE_POINT_PRICE = 0.01 ether;

    //      USER                TOKEN       AMOUNT
    mapping(address => mapping(address => uint256)) internal s_deposits;

    //   SolverOpHash   SolverOperation
    mapping(bytes32 => SolverOperation) public S_solverOpCache;

    //      UserOpHash  SolverOpHash[]
    mapping(bytes32 => bytes32[]) public S_solverOpHashes;

    //      USER        POINTS
    mapping(address => uint256) public S_userPointBalances;

    //      Ranking                         // Rebate (in Percentage)
    mapping(IMevReturnRanking.RankingType => uint256) S_rankingRebate;

    IPool public lending;

    event TokensRewarded(address indexed user, address indexed token, uint256 amount);

    constructor(
        address _atlas,
        address _rewardToken,
        address _lendingContract
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: true,
                trackUserReturnData: true,
                delegateUser: true,
                requirePreSolver: false,
                requirePostSolver: false,
                requirePostOps: true,
                zeroSolvers: true,
                reuseUserOp: true,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: true,
                invertBidValue: false,
                exPostBids: true,
                allowAllocateValueFailure: true
            })
        )
    {
        REWARD_TOKEN = _rewardToken;
        S_rankingRebate[IMevReturnRanking.RankingType.LOW] = 1000; // 10% in bps
        S_rankingRebate[IMevReturnRanking.RankingType.MEDIUM] = 3000; // 30% in bps
        S_rankingRebate[IMevReturnRanking.RankingType.HIGH] = 9000; // 90% in bps

        lending = IPool(_lendingContract);
    }

    // 1 point = 0.01 ETH
    function BorrowPointFlashloanProxyCall(
        UserOperation calldata userOp,
        address transferHelper,
        bytes calldata transferData,
        bytes32[] calldata solverOpHashes,
        uint256 borrowPointAmount
    )
        external
        payable
        withUserLock(userOp.from)
        onlyAsControl
    {
        // We don't want to borrow more than the maximum points in the pool.
        if (lending.getTotalAmount() > borrowPointAmount) {
            borrowPointAmount = lending.getTotalAmount();
        }

        uint256 tmpUserPoint = S_userPointBalances[userOp.from];
        tmpUserPoint += borrowPointAmount;

        // Decode the token information
        (Approval[] memory _approvals,,,,) =
            abi.decode(userOp.data[4:], (Approval[], address[], Beneficiary[], address, bytes));

        // Process token transfers if necessary.  If transferHelper == address(0), skip.
        if (transferHelper != address(0)) {
            (bool _success, bytes memory _data) = transferHelper.call(transferData);
            if (!_success) {
                assembly {
                    revert(add(_data, 32), mload(_data))
                }
            }

            // Get the execution environment address
            (address _environment,,) = IAtlas(ATLAS).getExecutionEnvironment(userOp.from, CONTROL);

            uint256 approvalLength = _approvals.length;
            for (uint256 i; i < approvalLength;) {
                uint256 _balance = IERC20(_approvals[i].token).balanceOf(address(this));
                if (_balance != 0) {
                    IERC20(_approvals[i].token).transfer(_environment, _balance);
                }
                unchecked {
                    ++i;
                }
            }
        }

        uint256 _bundlerRefundTracker = address(this).balance - msg.value;

        {
            (bool _success, bytes memory _data) =
                ATLAS.call{ value: msg.value }(abi.encodeCall(IAtlas.metacall, (userOp, _solverOps, _dAppOp)));
            if (!_success) {
                assembly {
                    revert(add(_data, 32), mload(_data))
                }
            }
        }

        // Return the flashloan amount to the pool
        address lendingAddr = address(lending);
        IERC20(lending.getPointsToken()).transfer(lendingAddr, borrowPointAmount);
        SafeTransferLib.safeTransferETH(lendingAddr, borrowPointAmount / ONE * ONE_POINT_PRICE);

        if (address(this).balance > _bundlerRefundTracker) {
            // Refund depending on the user RankingType
            // 30% for LOW, 50% for MEDIUM, 80% for HIGH
            uint256 refundAmount = address(this).balance - _bundlerRefundTracker;
            SafeTransferLib.safeTransferETH(
                msg.sender, refundAmount * S_rankingRebate[getUserRanking(msg.sender)] / ONE_BPS_BASIS
            );
        }
    }

    // 1 point = 0.005 ETH (Roulette point are less expensive due to randomness)
    function RouletteBundleRefundProxyCall(
        UserOperation calldata userOp,
        address transferHelper,
        bytes calldata transferData,
        bytes32[] calldata solverOpHashes
    )
        external
        payable
        withUserLock(userOp.from)
        onlyAsControl
    {
        // Decode the token information
        (Approval[] memory _approvals,,,,) =
            abi.decode(userOp.data[4:], (Approval[], address[], Beneficiary[], address, bytes));

        // Process token transfers if necessary.  If transferHelper == address(0), skip.
        if (transferHelper != address(0)) {
            (bool _success, bytes memory _data) = transferHelper.call(transferData);
            if (!_success) {
                assembly {
                    revert(add(_data, 32), mload(_data))
                }
            }

            // Get the execution environment address
            (address _environment,,) = IAtlas(ATLAS).getExecutionEnvironment(userOp.from, CONTROL);

            uint256 approvalLength = _approvals.length;
            for (uint256 i; i < approvalLength;) {
                uint256 _balance = IERC20(_approvals[i].token).balanceOf(address(this));
                if (_balance != 0) {
                    IERC20(_approvals[i].token).transfer(_environment, _balance);
                }
                unchecked {
                    ++i;
                }
            }
        }

        uint256 _bundlerRefundTracker = address(this).balance - msg.value;

        bytes32 _userOpHash = IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(userOp);

        DAppOperation memory _dAppOp = DAppOperation({
            from: address(this), // signer of the DAppOperation
            to: ATLAS, // Atlas address
            nonce: 0, // Atlas nonce of the DAppOperation available in the AtlasVerification contract
            deadline: userOp.deadline, // block.number deadline for the DAppOperation
            control: address(this), // DAppControl address
            bundler: address(this), // Signer of the atlas tx (msg.sender)
            userOpHash: _userOpHash, // keccak256 of userOp.to, userOp.data
            callChainHash: bytes32(0), // keccak256 of the solvers' txs
            signature: new bytes(0) // DAppOperation signed by DAppOperation.from
         });

        SolverOperation[] memory _solverOps = _getSolverOps(solverOpHashes);

        (bool _success, bytes memory _data) =
            ATLAS.call{ value: msg.value }(abi.encodeCall(IAtlas.metacall, (userOp, _solverOps, _dAppOp)));
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        if (address(this).balance > _bundlerRefundTracker) {
            // Refund depending on the user RankingType
            // 30% for LOW, 50% for MEDIUM, 80% for HIGH
            uint256 refundAmount = address(this).balance - _bundlerRefundTracker;
            uint256 randomNumber = block.prevrandao;
            SafeTransferLib.safeTransferETH(
                msg.sender, refundAmount * S_rankingRebate[IMevReturnRanking.RankingType(randomNumber)] / ONE_BPS_BASIS
            );
        }
    }

    function _allocateValueCall(address bidToken, uint256, bytes calldata returnData) internal override {
        // NOTE: The _user() receives any remaining balance after the other beneficiaries are paid.
        Beneficiary[] memory _beneficiaries = abi.decode(returnData, (Beneficiary[]));

        uint256 _unallocatedPercent = _FEE_BASE;
        uint256 _balance = address(this).balance;

        // Return the receivable tokens to the user
        uint256 beneficiariesLength = _beneficiaries.length;
        for (uint256 i; i < beneficiariesLength; i++) {
            uint256 _percentage = _beneficiaries[i].percentage;
            if (_percentage < _unallocatedPercent) {
                _unallocatedPercent -= _percentage;
                SafeTransferLib.safeTransferETH(_beneficiaries[i].owner, _balance * _percentage / _FEE_BASE);
            } else {
                SafeTransferLib.safeTransferETH(_beneficiaries[i].owner, address(this).balance);
            }
        }

        // Transfer the remaining value to the user
        if (_unallocatedPercent != 0) {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);
        }
    }

    function _postOpsCall(bool, bytes calldata data) internal override {
        address tokenSold = abi.decode(data, (address));
        uint256 balance;

        address user = _user();

        if (tokenSold == address(0)) {
            balance = address(this).balance;
            if (balance > 0) {
                balance = balance * S_rankingRebate[getUserRanking(user)] / ONE_BPS_BASIS;
                SafeTransferLib.safeTransferETH(user, balance);
            }
        } else {
            balance = IERC20(tokenSold).balanceOf(address(this));
            if (balance > 0) {
                balance = balance * S_rankingRebate[getUserRanking(user)] / ONE_BPS_BASIS;
                SafeTransferLib.safeTransfer(tokenSold, user, balance);
            }
        }
        // Increment point for future rebate
        S_userPointBalances[user] += 1;
    }

    // Modifiers from Ranking
    modifier onlyAsControl() {
        if (address(this) != CONTROL) revert();
        _;
    }

    modifier withUserLock(address user) {
        if (_userLock != address(1)) revert();
        _userLock = user;
        _;
        _userLock = address(1);
    }

    modifier onlyWhenUnlocked() {
        if (_userLock != address(1)) revert();
        _;
    }

    // Additional functions from Ranking
    function getUser() external view onlyAsControl returns (address) {
        address _user = _userLock;
        if (_user == address(1)) revert();
        return _user;
    }

    function addSolverOp(SolverOperation calldata solverOp) external onlyAsControl {
        if (msg.sender != solverOp.from) revert();

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));

        S_solverOpCache[_solverOpHash] = solverOp;
        S_solverOpHashes[solverOp.userOpHash].push(_solverOpHash);
    }

    function _getSolverOps(bytes32[] calldata solverOpHashes)
        internal
        view
        returns (SolverOperation[] memory solverOps)
    {
        uint256 solverHashLength = solverOpHashes.length;
        solverOps = new SolverOperation[](solverHashLength);

        uint256 _j;
        for (uint256 i; i < solverHashLength;) {
            SolverOperation memory _solverOp = S_solverOpCache[solverOpHashes[i]];
            if (_solverOp.from != address(0)) {
                solverOps[_j++] = _solverOp;
            }
            unchecked {
                ++i;
            }
        }
    }

    // Getters and helpers from V2RewardDAppControl
    function getBidFormat(UserOperation calldata) public view override returns (address bidToken) {
        return REWARD_TOKEN;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    // Ranking functions
    function getUserRanking(address user) public view returns (IMevReturnRanking.RankingType) {
        uint256 points = S_userPointBalances[user];
        if (points == 0) {
            return IMevReturnRanking.RankingType.LOW;
        } else if (points < 100) {
            return IMevReturnRanking.RankingType.MEDIUM;
        } else {
            return IMevReturnRanking.RankingType.HIGH;
        }
    }
}
