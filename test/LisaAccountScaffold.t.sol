// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LisaAccount} from "../src/LisaAccount.sol";
import {ILisaAccount} from "../src/interfaces/ILisaAccount.sol";

contract LisaAccountScaffoldTest is Test {
    function testIntegrationInterfaceSelectors() public pure {
        assertEq(ILisaAccount.lisaRuntime.selector, bytes4(keccak256("lisaRuntime()")));
        assertEq(ILisaAccount.executeLisa.selector, bytes4(keccak256("executeLisa(bytes)")));
    }
}
