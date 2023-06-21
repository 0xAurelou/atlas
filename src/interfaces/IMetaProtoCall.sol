//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall
} from "../libraries/DataTypes.sol";

interface IMetaProtoCall {
    function metacall(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable;
}