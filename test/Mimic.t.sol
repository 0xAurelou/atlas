// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Mimic } from "src/contracts/atlas/Mimic.sol";

contract MimicTest is Test {
    function testMimicDelegatecall() public {
        // Deploy mimic
        Mimic mimic = new Mimic();
        deployCodeTo("Mimic.t.sol:MimicDelegateCheck", 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa);
        // Check it is delegatecalled and data pass is correct
        vm.expectEmit(true, true, true, true);
        bytes memory passedData = hex"01";
        emit MimicDelegateCheck.DelegateCalled(abi.encodePacked(
            passedData,
            address(0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB),
            address(0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC),
            uint32(0x22222222),
            bytes32(uint256(0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee))
        ));
        (bool success, bytes memory data) = address(mimic).call(passedData);
        assertEq(success, true);
        assertEq(data, hex"0001");
    }
}

contract MimicDelegateCheck {
    event DelegateCalled(bytes data);

    address immutable original;
    constructor() {
        original = address(this);
    }

    fallback(bytes calldata) external returns (bytes memory) {
        if(address(this) == original) {
            revert("Not delegatecall");
        }
        emit DelegateCalled(msg.data);
        return hex"0001";
    }
}
