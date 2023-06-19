//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

enum ExecutionPhase {
    Uninitialized,
    Staging,
    UserCall,
    SearcherCalls,
    Verification
}

struct ProtocolData {
    address owner; // the protocol, not fastlane
    uint32 nonce; 
    uint16 callConfig; // bitwise
    uint16 split; // FL revenue share
}

enum CallConfig { // for readability, will get broken down into pure funcs later
    CallStaging,
    DelegateStaging,
    FwdValueStaging,
    CallVerification,
    DelegateVerification,
    FwdValueVerification
}

enum SearcherSafety {
    Unset,
    Requested,
    Verified
}

struct SearcherMetaTx {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
    uint256 maxFeePerGas; // maxFeePerGas searcher is willing to pay.  This goes to validator, not protocol or user
    bytes32 bidsHash; // searcher's backend must keccak256() their BidData array and include that in the signed meta tx, which we then verify on chain. 
    bytes data;
}

struct BidData {
    address token;
    uint256 bidAmount;
}

struct SearcherCall {
    SearcherMetaTx metaTx;
    bytes signature;
    BidData[] bids;
}

/// @notice contract call set by front end to prepare state for user's call (IE token transfers to address(this))
/// @param to address to call
/// @param stagingSelector func selector to call
/// @dev This is set by the front end!
/// @dev The stagingSelector's argument types must match the user's call's argument types to properly stage the meta tx.
struct StagingCall { 
    address to;
    uint16 callConfig;
    bytes4 stagingSelector;
    bytes4 verificationSelector;
    bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
    
    // TODO: allow option for protocol frontends (via relay) to sign this data to prevent hostile users 
    // from tampering w/ it
    // NOTE: protocols opting to sign the staging call should be strongly discouraged from doing so as 
    // the necessity for staging data to be trustless would also imply the existence of attack vectors
    // that could potentially be accessed by other means. (might be useful for CLOBs tho)
}

struct UserCall {
    address to;
    address from;
    uint256 gas;
    uint256 value;
    bytes data;
}

/// @notice protocol payee Data Struct
/// @param token token address (ERC20) being paid
struct PayeeData {
    address token;
    PaymentData[] payments;
}

/// @param payee address to pay
/// @param payeePercent percentage of bid to pay to payee (base 100)
/// @dev must sum to 100
struct PaymentData {
    address payee;
    uint256 payeePercent;
    bytes4 pmtSelector; // func selector (on payee contract) to call for custom pmt function. leave blank if payee receives funds via ERC20 transfer
    // TODO: formalize / customize args for pmtSelector?
}

enum SearcherOutcome {
    // future task tracking
    PendingUpdate,
    ExecutionCompleted,
    UpdateCompleted,
    BlockExecution,

    // no user refund (relay error or hostile user)
    InvalidSignature,
    InvalidUserHash,
    InvalidBidsHash,
    GasPriceOverCap,
    UserOutOfGas,

    // calldata user refund from searcher
    InsufficientEscrow,
    InvalidNonceOver,

    // no call, but full user refund
    AlreadyExecuted,
    InvalidNonceUnder,
    PerBlockLimit, // searchers can only send one tx per block 
    // if they sent two we wouldn't be able to flag builder censorship
    InvalidFormat,

    // protocol / external user refund (TODO: keep?)
    NotWinner, // a higher bidding searcher was successful
    
    // call, with full user refund
    CallReverted,
    BidNotPaid,
    Success
}

contract FastLaneDataTypes {

    uint256 constant public SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 constant public VALIDATION_GAS_LIMIT = 500_000;
    uint256 constant public GWEI = 1_000_000_000;
    uint256 constant public SEARCHER_GAS_BUFFER = 5; // out of 100

    bytes32 internal constant _TYPE_HASH =
        keccak256("SearcherMetaTx(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes32 userCallHash,uint256 maxFeePerGas,bytes32 bidsHash,bytes data)");

    uint256 constant internal _NO_REFUND = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) 
    );

    uint256 constant internal _CALLDATA_REFUND = (
        1 << uint256(SearcherOutcome.InsufficientEscrow) |
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.UserOutOfGas) 
    );

    uint256 constant internal _FULL_REFUND = (
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat)
    );

    uint256 constant internal _EXTERNAL_REFUND = (
        1 << uint256(SearcherOutcome.NotWinner)
    );

    uint256 constant internal _EXECUTION_REFUND = (
        1 << uint256(SearcherOutcome.CallReverted) |
        1 << uint256(SearcherOutcome.BidNotPaid) |
        1 << uint256(SearcherOutcome.Success)
    );

    uint256 constant internal _NO_NONCE_UPDATE = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder)
    );

    uint256 constant internal _BLOCK_VALID_EXECUTION = (
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) |
        1 << uint256(SearcherOutcome.UserOutOfGas) |
        1 << uint256(SearcherOutcome.NotWinner)
    );


}