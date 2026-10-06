// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {SetDelegation} from "../script/SetDelegation.s.sol";

contract ExposedSetDelegation is SetDelegation {
    address private _accountOverride;

    /// @dev Stands in for the signing account, which tests do not have.
    function _account() internal view override returns (address) {
        return _accountOverride;
    }

    function setAccount(address account) external {
        _accountOverride = account;
    }

    function designator(bytes memory code) external pure returns (address) {
        return _delegationDesignator(code);
    }

    function authorizationDigest(address implementation, uint64 nonce) external view returns (bytes32) {
        return _authorizationDigest(implementation, nonce);
    }
}

/// @dev Covers the authorization digest and the paths that decide whether to broadcast. Broadcasting
///      itself is unsupported in tests, as is discovering a signing account, so the full path was
///      verified against a local Prague node; see "Setting the delegation" in the README.
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

    /// @dev The hand-built digest must agree with the one Forge signs for itself, byte for byte.
    function testAuthorizationDigestMatchesForgeHelper() public {
        address implementation = address(0x1234);
        uint64 nonce = 7;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ACCOUNT_KEY, script.authorizationDigest(implementation, nonce));
        Vm.SignedDelegation memory expected = vm.signDelegation(implementation, ACCOUNT_KEY, nonce);

        assertEq(uint256(v - 27), uint256(expected.v));
        assertEq(r, expected.r);
        assertEq(s, expected.s);
        assertEq(expected.implementation, implementation);
        assertEq(expected.nonce, nonce);
    }

    function testAuthorizationDigestIsChainScoped() public {
        address implementation = address(0x1234);
        bytes32 local = script.authorizationDigest(implementation, 1);

        vm.chainId(1);
        assertTrue(local != script.authorizationDigest(implementation, 1), "digest ignores the chain id");
    }

    /// @dev Drives every `run()` path from one test: `vm.setEnv` is process-wide, and forge runs test
    ///      functions concurrently, so env-backed inputs must not be split across functions.
    function testRunGuardPaths() public {
        address account = vm.addr(ACCOUNT_KEY);
        address target = address(0x1111);
        address other = address(0x2222);
        script.setAccount(account);

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
