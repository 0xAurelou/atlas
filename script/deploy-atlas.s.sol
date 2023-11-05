// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {DeployBaseScript} from "script/base/deploy-base.s.sol";

import {Atlas} from "src/contracts/atlas/Atlas.sol";
import {AtlasFactory} from "src/contracts/atlas/AtlasFactory.sol";
import {AtlasVerification} from "src/contracts/atlas/AtlasVerification.sol";
import {SwapIntentController} from "src/contracts/examples/intents-example/SwapIntent.sol";
import {TxBuilder} from "src/contracts/helpers/TxBuilder.sol";
import {Simulator} from "src/contracts/helpers/Simulator.sol";

contract DeployAtlasScript is DeployBaseScript {
    // TODO move commons vars like these to base deploy script
    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    Simulator public simulator;

    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        simulator = new Simulator();
        atlas = new Atlas(64, address(simulator), address(0), address(0)); //TODO update to Factory and Verification addr arg
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SIMULATOR", address(simulator));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
    }
}

contract DeployAtlasAndSwapIntentDAppControlScript is DeployBaseScript {
    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    Simulator public simulator;
    SwapIntentController public swapIntentControl;

    function run() external {
        console.log("\n=== DEPLOYING Atlas and SwapIntent DAppControl ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the Atlas contract
        simulator = new Simulator();
        atlas = new Atlas(64, address(simulator), address(0), address(0)); //TODO update to Factory and Verification addr arg
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlasVerification.initializeGovernance(address(swapIntentControl));
        atlasVerification.integrateDApp(address(swapIntentControl));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SIMULATOR", address(simulator));
        _writeAddressToDeploymentsJson(".SWAP_INTENT_DAPP_CONTROL", address(swapIntentControl));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
    }
}

contract DeployAtlasAndSwapIntentDAppControlAndTxBuilderScript is DeployBaseScript {
    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    Simulator public simulator;
    SwapIntentController public swapIntentControl;
    TxBuilder public txBuilder;

    function run() external {
        console.log("\n=== DEPLOYING Atlas and SwapIntent DAppControl and TxBuilder ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the Atlas contract
        simulator = new Simulator();
        atlas = new Atlas(64, address(simulator), address(0), address(0)); //TODO update to Factory and Verification addr arg
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlasVerification.initializeGovernance(address(swapIntentControl));
        atlasVerification.integrateDApp(address(swapIntentControl));

        // Deploy the TxBuilder
        txBuilder = new TxBuilder(address(swapIntentControl), address(atlas), address(atlas));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SIMULATOR", address(simulator));
        _writeAddressToDeploymentsJson(".SWAP_INTENT_DAPP_CONTROL", address(swapIntentControl));
        _writeAddressToDeploymentsJson(".TX_BUILDER", address(txBuilder));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
        console.log("TxBuilder deployed at: \t\t\t", address(txBuilder));
    }
}
