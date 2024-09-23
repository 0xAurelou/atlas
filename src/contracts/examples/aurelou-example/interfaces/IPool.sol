// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

interface IPool {
    function getTotalAmount() external view returns (uint256);

    function getPointsToken() external view returns (address);
}
