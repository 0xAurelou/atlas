// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {ProtocolCall, UserCall, SearcherCall} from "../src/contracts/types/CallTypes.sol";
import {Verification} from "../src/contracts/types/VerificationTypes.sol";

import {SwapIntentController, SwapIntent} from "src/contracts/intents-example/SwapIntent.sol";
import {SearcherBase} from "../src/contracts/searcher/SearcherBase.sol";

// QUESTIONS:

// Refactor Ideas:
// 1. Lots of bitwise operations explicitly coded in contracts - could be a helper lib thats more readable
// 2. helper is currently a V2Helper and shared from BaseTest. Should only be in Uni V2 related tests
// 3. Need a more generic helper for BaseTest
// 4. Gonna be lots of StackTooDeep errors. Maybe need a way to elegantly deal with that in BaseTest
// 5. Change metaFlashCall structure in SearcherBase - maybe virtual fn to be overridden, which hooks for checks
// 6. Maybe emit error msg or some other better UX for error if !valid in metacall()

// Doc Ideas:
// 1. Step by step instructions for building a metacall transaction (for internal testing, and integrating protocols)

// To Understand Better:
// 1. The lock system (and look for any gas optimizations / ways to reduce lock actions)

contract SwapIntentTest is BaseTest {
    SwapIntentController public swapIntentController;
    TxBuilder public txBuilder;
    Sig public sig;

    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller) 
        governancePK = 11112;
        governanceEOA = vm.addr(governancePK);
        console.log("governanceEOA", governanceEOA);

        // Deploy new SwapIntent Controller from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        swapIntentController = new SwapIntentController(address(escrow));        
        atlas.initializeGovernance(address(swapIntentController));
        atlas.integrateProtocol(address(swapIntentController), address(swapIntentController));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            protocolControl: address(swapIntentController),
            escrowAddress: address(escrow),
            atlasAddress: address(atlas)
        });
    }

    function testAtlasSwapUsingIntent() public {
        // Swap 10 WETH for 20 DAI
        SwapIntent memory swapIntent = SwapIntent({
            tokenUserBuys: DAI_ADDRESS,
            amountUserBuys: 20e18,
            tokenUserSells: WETH_ADDRESS,
            amountUserSells: 10e18,
            surplusToken: address(0)
        });

        // Searcher deploys the RFQ searcher contract (defined at bottom of this file)
        vm.startPrank(searcherOneEOA);
        SimpleRFQSearcher rfqSearcher = new SimpleRFQSearcher(address(atlas));
        atlas.deposit{value: 1e18}(searcherOneEOA);
        vm.stopPrank();

        // Give 20 DAI to RFQ searcher contract
        deal(DAI_ADDRESS, address(rfqSearcher), swapIntent.amountUserBuys);
        assertEq(DAI.balanceOf(address(rfqSearcher)), swapIntent.amountUserBuys, "Did not give enough DAI to searcher");

        // Input params for Atlas.metacall() - will be populated below
        ProtocolCall memory protocolCall = txBuilder.getProtocolCall();
        UserCall memory userCall;
        SearcherCall[] memory searcherCalls = new SearcherCall[](1);
        Verification memory verification;

        vm.startPrank(userEOA);
        address executionEnvironment = atlas.createExecutionEnvironment(protocolCall);
        vm.stopPrank();
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        // userCallData is used in delegatecall from exec env to control, calling stagingCall
        // first 4 bytes are "userSelector" param in stagingCall in ProtocolControl - swap() selector
        // rest of data is "userData" param
        
        // swap(SwapIntent calldata) selector = 0x98434997
        bytes memory userCallData = abi.encodeWithSelector(SwapIntentController.swap.selector, swapIntent);

        // Builds the metaTx and to parts of userCall, signature still to be set
        userCall = txBuilder.buildUserCall({
            from: userEOA, // NOTE: Would from ever not be user?
            to: address(swapIntentController),
            maxFeePerGas: tx.gasprice + 1, // TODO update
            value: 0,
            data: userCallData
        });

        // User signs the userCall
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlas.getUserCallPayload(userCall));
        userCall.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Build searcher calldata (function selector on searcher contract and its params)
        bytes memory searcherCallData = abi.encodeWithSelector(
            SimpleRFQSearcher.fulfillRFQ.selector, 
            swapIntent,
            executionEnvironment
        );

        // Builds the SearcherCall
        searcherCalls[0] = txBuilder.buildSearcherCall({
            userCall: userCall,
            protocolCall: protocolCall,
            searcherCallData: searcherCallData,
            searcherEOA: searcherOneEOA,
            searcherContract: address(rfqSearcher),
            bidAmount: 1e18
        });

        // Searcher signs the searcherCall
        (sig.v, sig.r, sig.s) = vm.sign(searcherOnePK, atlas.getSearcherPayload(searcherCalls[0].metaTx));
        searcherCalls[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Frontend creates verification calldata after seeing rest of data
        verification = txBuilder.buildVerification(governanceEOA, protocolCall, userCall, searcherCalls);

        // Frontend signs the verification payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlas.getVerificationPayload(verification));
        verification.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Check user token balances before
        uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);
        uint256 userDaiBalanceBefore = DAI.balanceOf(userEOA);
        assertTrue(userWethBalanceBefore > swapIntent.amountUserSells, "Not enough starting WETH");

        vm.startPrank(userEOA);
        WETH.approve(address(atlas), swapIntent.amountUserSells);
        // NOTE: Should metacall return something? Feels like a lot of data you might want to know about the tx
        atlas.metacall({
            protocolCall: protocolCall,
            userCall: userCall,
            searcherCalls: searcherCalls,
            verification: verification
        });
        vm.stopPrank();

        // Check user token balances after
        assertEq(WETH.balanceOf(userEOA), userWethBalanceBefore - swapIntent.amountUserSells, "Did not spend enough WETH");
        assertEq(DAI.balanceOf(userEOA), userDaiBalanceBefore + swapIntent.amountUserBuys, "Did not receive enough DAI");
    }
}


contract SimpleRFQSearcher is SearcherBase {
    constructor(address atlas) SearcherBase(atlas, msg.sender) {}

    function fulfillRFQ(
        SwapIntent calldata swapIntent,
        address executionEnvironment
    ) public {
        require(ERC20(swapIntent.tokenUserSells).balanceOf(address(this)) >= swapIntent.amountUserSells, "Did not receive enough tokenIn");
        require(ERC20(swapIntent.tokenUserBuys).balanceOf(address(this)) >= swapIntent.amountUserBuys, "Not enough tokenOut to fulfill");
        ERC20(swapIntent.tokenUserBuys).transfer(executionEnvironment, swapIntent.amountUserBuys);
    }

    fallback() external payable {}
    receive() external payable {}
}