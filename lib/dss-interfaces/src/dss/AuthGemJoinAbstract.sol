// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface AuthGemJoinAbstract {
    function dec() external view returns (uint256);
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function join(address, uint256, address) external;
    function exit(address, uint256) external;
}
