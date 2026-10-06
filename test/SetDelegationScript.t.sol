// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {SetDelegation} from "../script/SetDelegation.s.sol";

/// @dev Exposes the script's designator parser, which is internal.
contract ExposedSetDelegation is SetDelegation {
    function designator(bytes memory code) external pure returns (address) {
        return _delegationDesignator(code);
    }
}

/// @dev Covers the paths that decide whether to broadcast. The broadcast itself cannot run in tests
///      (`broadcast` is unsupported there); it was verified end-to-end against a local Prague node,
///      following "Setting the delegation" in the README.
contract SetDelegationScriptTest is Test {
    uint256 internal constant ACCOUNT_KEY = 0xA11CE;

    ExposedSetDelegation internal script;

    function setUp() public {
        script = new ExposedSetDelegation();
    }

    function testParsesDesignatorAddress() public view {
        assertEq(script.designator(abi.encodePacked(hex"ef0100", address(0xBEEF))), address(0xBEEF));
        assertEq(script.designator(abi.encodePacked(hex"ef0100", address(0xA11CE))), address(0xA11CE));
    }

    function testParsesNonDesignatorCodeAsZero() public view {
        assertEq(script.designator(""), address(0));
        assertEq(script.designator(hex"600160005500"), address(0));
        assertEq(script.designator(abi.encodePacked(hex"ef0200", address(0xBEEF))), address(0));
        assertEq(script.designator(abi.encodePacked(hex"ef0100", address(0xBEEF), hex"00")), address(0));
    }

    /// @dev Drives every `run()` path from one test: `vm.setEnv` is process-wide, and forge runs
    ///      test functions concurrently, so env-backed inputs must not be split across functions.
    function testRunGuardPaths() public {
        address account = vm.addr(ACCOUNT_KEY);
        address target = address(0x1111);
        address other = address(0x2222);
        vm.setEnv("PRIVATE_KEY", vm.toString(ACCOUNT_KEY));

        // Already delegated where requested: return the account without broadcasting.
        vm.etch(account, abi.encodePacked(hex"ef0100", target));
        vm.setEnv("DELEGATION_TARGET", vm.toString(target));
        assertEq(script.run(), account);

        // Delegated elsewhere: never replace a delegation implicitly.
        vm.etch(account, abi.encodePacked(hex"ef0100", other));
        vm.expectRevert(abi.encodeWithSelector(SetDelegation.AlreadyDelegated.selector, account, other));
        script.run();

        // An address holding real code rather than a delegation.
        bytes memory code = hex"600160005500";
        vm.etch(account, code);
        vm.expectRevert(abi.encodeWithSelector(SetDelegation.UnexpectedCode.selector, account, code.length));
        script.run();

        // Unusable targets are rejected before the account code is even read.
        vm.setEnv("DELEGATION_TARGET", vm.toString(address(0)));
        vm.expectRevert(abi.encodeWithSelector(SetDelegation.InvalidTarget.selector, address(0), account));
        script.run();

        vm.setEnv("DELEGATION_TARGET", vm.toString(account));
        vm.expectRevert(abi.encodeWithSelector(SetDelegation.InvalidTarget.selector, account, account));
        script.run();
    }
}
