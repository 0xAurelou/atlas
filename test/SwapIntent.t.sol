// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {ProtocolCall, UserCall, SearcherCall} from "../src/contracts/types/CallTypes.sol";
import {Verification} from "../src/contracts/types/VerificationTypes.sol";

import {SwapIntentController, SwapIntent} from "src/contracts/intents-example/SwapIntent.sol";

// QUESTIONS:
// 1. What is escrowDuration (constructor arg in Atlas, Escrow.sol)? Where is it used?
// 2. Is the Atlas contract always also the Escrow contract? Would Escrow ever be separate?
// 3. What is staging call and staging lock? How does it work?
//      A: Checks protocolCall config for requireStaging, then calls holdStagingLock() on EscrowKey
// 4. When is SwapIntentController deployed and where is it called or passed as arg
//      A: SwapIntentContoller is ProtocolControl, must be deployed and passed into txBuilder

// Refactor Ideas:
// 1. Lots of bitwise operations explicitly coded in contracts - could be a helper lib thats more readable
// 2. helper is currently a V2Helper and shared from BaseTest. Should only be in Uni V2 related tests
// 3. Need a more generic helper for BaseTest

// Doc Ideas:
// 1. Step by step instructions for building a metacall transaction (for internal testing, and integrating protocols)


contract SwapIntentTest is BaseTest {
    SwapIntentController public swapIntentController;
    TxBuilder public txBuilder;

    function setUp() public virtual override {
        BaseTest.setUp();

        swapIntentController = new SwapIntentController(address(escrow));

        txBuilder = new TxBuilder({
            protocolControl: address(swapIntentController),
            escrowAddress: address(escrow),
            atlasAddress: address(atlas)
        });
    }

    function testAtlasSwapUsingIntent() public {
        // Swap 10 WETH for 20 FXS

        // Input params for Atlas.metacall() - will be populated below
        ProtocolCall memory protocolCall;
        UserCall memory userCall;
        SearcherCall[] memory searcherCalls = new SearcherCall[](1); 
        SearcherCall memory searcherCall; // First and only searcher will succeed
        Verification memory verification; 

        protocolCall = txBuilder.getProtocolCall();

        // userCallData is used in delegatecall from exec env to control, calling stagingCall
        // first 4 bytes are "userSelector" param in stagingCall in ProtocolControl - swap() selector
        // rest of data is "userData" param
        SwapIntent memory swapIntent = SwapIntent({
            tokenUserBuys: FXS_ADDRESS,
            amountUserBuys: 20e18,
            tokenUserSells: WETH_ADDRESS, 
            amountUserSells: 10e18,
            surplusToken: address(0)
        });
        // swap(SwapIntent calldata) selector = 0x98434997
        bytes memory userCallData = abi.encodeWithSelector(SwapIntentController.swap.selector, swapIntent);
        console.log("userCallData:");
        console.logBytes(userCallData);

        // Builds the metaTx and to parts of userCall, signature still to be set
        userCall = txBuilder.buildUserCall({
            from: userEOA, // NOTE: Would from ever not be user?
            to: address(atlas),
            maxFeePerGas: 0, // TODO update
            value: 0,
            data: userCallData
        });

        // searcherCallData is similar to userCallData
        // decodes to [bytes stagingReturnData, address searcherTo]
        // where stagingReturnData decodes to SwapIntent (same as in userCallData)
        bytes memory searcherCallData = abi.encode(swapIntent, searcherOneEOA);
        console.log("searcherCallData:");
        console.logBytes(searcherCallData);

        // Builds the SearcherCall
        searcherCall = txBuilder.buildSearcherCall({
            userCall: userCall,
            protocolCall: protocolCall,
            searcherCallData: searcherCallData,
            searcherEOA: searcherOneEOA,
            searcherContract: address(searcherOne), // TODO 
            bidAmount: 1e18
        });

        searcherCalls[0] = searcherCall;


        // Frontend creates verification after seeing rest of data
        // verification;


        address executionEnvironment = atlas.createExecutionEnvironment(protocolCall);
        vm.label(address(executionEnvironment), "EXECUTION ENV");


        console.log("userEOA", userEOA);
        console.log("atlas", address(atlas)); // ATLAS == ESCROW
        console.log("escrow", address(escrow)); // ATLAS == ESCROW
        console.log("control", address(control));
        console.log("executionEnvironment", executionEnvironment);





        vm.startPrank(userEOA);
        // NOTE: Should metacall return something? Feels like a lot of data you might want to know about the tx
        atlas.metacall({
            protocolCall: protocolCall,
            userCall: userCall,
            searcherCalls: searcherCalls,
            verification: verification
        });
        vm.stopPrank();



    }

}