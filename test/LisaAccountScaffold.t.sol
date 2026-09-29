// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {LisaAccount} from "../src/LisaAccount.sol";
import {ILisaAccount} from "../src/interfaces/ILisaAccount.sol";

contract MockLisaRuntime {
    error RuntimeFailure();

    event RuntimeExecuted(address indexed self, address indexed caller, uint256 value, bytes program);

    fallback() external payable {
        if (msg.data.length == 1 && msg.data[0] == 0xff) revert RuntimeFailure();
        emit RuntimeExecuted(address(this), msg.sender, msg.value, msg.data);
    }
}

contract BatchTarget {
    error BatchFailure();

    uint256 public value;

    function setValue(uint256 next) external payable {
        value = next;
    }

    function fail() external pure {
        revert BatchFailure();
    }
}

contract LisaAccountTest is Test {
    bytes32 internal constant BATCH_MODE = bytes32(uint256(1) << 248);
    uint256 internal constant ACCOUNT_KEY = 0xA11CE;
    uint256 internal constant OTHER_KEY = 0xB0B;

    event RuntimeExecuted(address indexed self, address indexed caller, uint256 value, bytes program);

    MockLisaRuntime internal runtime;
    LisaAccount internal implementation;

    function setUp() public {
        runtime = new MockLisaRuntime();
        implementation = new LisaAccount(address(runtime));
    }

    function _delegatedAccount(uint256 privateKey) internal returns (address account) {
        account = vm.addr(privateKey);
        vm.etch(account, address(implementation).code);
    }

    function testRuntimeIsImmutableInImplementationAndDelegatedCode() public {
        assertEq(implementation.lisaRuntime(), address(runtime));

        address account = _delegatedAccount(ACCOUNT_KEY);
        assertEq(ILisaAccount(account).lisaRuntime(), address(runtime));
    }

    function testDeploymentRejectsAddressWithoutCode() public {
        address missingRuntime = address(0xBEEF);

        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, missingRuntime));
        new LisaAccount(missingRuntime);
    }

    function testExecuteLisaRejectsExternalCaller() public {
        vm.expectRevert(abi.encodeWithSelector(Account.AccountUnauthorized.selector, address(this)));
        implementation.executeLisa(hex"01");
    }

    function testExecuteLisaRunsRuntimeInDelegatedAccountContext() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        bytes memory program = hex"123456";

        vm.expectEmit(true, true, false, true, account);
        emit RuntimeExecuted(account, account, 0, program);

        vm.prank(account);
        ILisaAccount(account).executeLisa(program);
    }

    function testExecuteLisaBubblesRuntimeRevert() public {
        address account = _delegatedAccount(ACCOUNT_KEY);

        vm.expectRevert(MockLisaRuntime.RuntimeFailure.selector);
        vm.prank(account);
        ILisaAccount(account).executeLisa(hex"ff");
    }

    function testERC1271AcceptsTheEOASignature() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        bytes32 hash = keccak256("lisa-account");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ACCOUNT_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(IERC1271(account).isValidSignature(hash, signature), IERC1271.isValidSignature.selector);
    }

    function testERC1271RejectsAnotherSigner() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        bytes32 hash = keccak256("lisa-account");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OTHER_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(IERC1271(account).isValidSignature(hash, signature), bytes4(0xffffffff));
    }

    function testERC7821AllowsSelfAuthorizedAtomicBatch() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        BatchTarget first = new BatchTarget();
        BatchTarget second = new BatchTarget();

        Execution[] memory calls = new Execution[](2);
        calls[0] = Execution({target: address(first), value: 0, callData: abi.encodeCall(BatchTarget.setValue, (11))});
        calls[1] = Execution({target: address(second), value: 0, callData: abi.encodeCall(BatchTarget.setValue, (22))});

        vm.prank(account);
        LisaAccount(payable(account)).execute(BATCH_MODE, abi.encode(calls));

        assertEq(first.value(), 11);
        assertEq(second.value(), 22);
    }

    function testERC7821AllowsEntryPoint() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        BatchTarget target = new BatchTarget();

        Execution[] memory calls = new Execution[](1);
        calls[0] = Execution({target: address(target), value: 0, callData: abi.encodeCall(BatchTarget.setValue, (7))});

        vm.prank(address(LisaAccount(payable(account)).entryPoint()));
        LisaAccount(payable(account)).execute(BATCH_MODE, abi.encode(calls));

        assertEq(target.value(), 7);
    }

    function testERC7821RejectsOtherCallers() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        Execution[] memory calls = new Execution[](0);

        vm.expectRevert(abi.encodeWithSelector(Account.AccountUnauthorized.selector, address(this)));
        LisaAccount(payable(account)).execute(BATCH_MODE, abi.encode(calls));
    }

    function testERC7821BatchIsAtomic() public {
        address account = _delegatedAccount(ACCOUNT_KEY);
        BatchTarget target = new BatchTarget();

        Execution[] memory calls = new Execution[](2);
        calls[0] = Execution({target: address(target), value: 0, callData: abi.encodeCall(BatchTarget.setValue, (99))});
        calls[1] = Execution({target: address(target), value: 0, callData: abi.encodeCall(BatchTarget.fail, ())});

        vm.expectRevert(BatchTarget.BatchFailure.selector);
        vm.prank(account);
        LisaAccount(payable(account)).execute(BATCH_MODE, abi.encode(calls));

        assertEq(target.value(), 0);
    }
}
