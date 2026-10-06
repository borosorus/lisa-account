// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Points an EOA at a LisaAccount implementation through an EIP-7702 delegation.
/// @dev The transaction is sent by the EOA itself and carries the signed authorization in its
///      authorization list, so no third party ever holds the delegation. The authorization is
///      chain-scoped: it is only valid on the chain it was signed for.
contract SetDelegation is Script {
    /// @notice LisaAccount implementation deployed on Ethereum Mainnet (see README).
    address internal constant DEFAULT_DELEGATION_TARGET = 0xE702F9FB288Bb97d359DA5eCB42532EAC6078871;

    /// @notice EIP-7702 delegation designator prefix, followed by a 20-byte address.
    bytes3 internal constant DELEGATION_PREFIX = 0xef0100;

    uint256 private constant PREFIX_LENGTH = 3;
    uint256 private constant DESIGNATOR_LENGTH = PREFIX_LENGTH + 20;

    /// @notice The EOA already delegates to another implementation.
    error AlreadyDelegated(address account, address current);

    /// @notice The EOA is an account whose code is not an EIP-7702 delegation.
    error UnexpectedCode(address account, uint256 codeLength);

    /// @notice The target is unusable as a delegation designator.
    error InvalidTarget(address target, address account);

    /// @notice The transaction carrying the authorization reverted.
    error DelegationTransactionFailed(address account, address target);

    function run() external returns (address account) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address target = vm.envOr("DELEGATION_TARGET", DEFAULT_DELEGATION_TARGET);
        account = vm.addr(privateKey);

        if (target == address(0) || target == account) revert InvalidTarget(target, account);

        bytes memory current = account.code;
        if (current.length != 0) {
            address delegated = _delegationDesignator(current);
            if (delegated == address(0)) revert UnexpectedCode(account, current.length);
            if (delegated != target) revert AlreadyDelegated(account, delegated);

            console.log("already delegated to the requested implementation; nothing to do");
            console.log("  account: %s", vm.toString(account));
            console.log("  target:  %s", vm.toString(target));
            return account;
        }

        console.log("setting EIP-7702 delegation");
        console.log("  account:            %s", vm.toString(account));
        console.log("  target:             %s", vm.toString(target));
        console.log("  chain id:           %s", vm.toString(block.chainid));
        // An offline dry run has no state, so a zero size there is expected, not a verdict.
        console.log("  target code size:   %s", vm.toString(target.code.length));

        vm.startBroadcast(privateKey);
        Vm.SignedDelegation memory authorization = vm.signAndAttachDelegation(target, privateKey);
        console.log("  authorization nonce: %s", vm.toString(authorization.nonce));

        // The empty self-call is what the authorization rides on. It doubles as a smoke test: if the
        // delegated code rejects an empty call, the whole transaction reverts, so the delegation does
        // not stick either.
        (bool executed,) = account.call("");
        if (!executed) revert DelegationTransactionFailed(account, target);
        vm.stopBroadcast();
    }

    /// @dev Reads the designator out of `0xef0100 <address>` code, or returns zero if the code is
    ///      not a delegation indicator.
    /// @dev The designator always fits in the code's first word, so it is read as a word and
    ///      shifted rather than sliced: Solidity cannot slice `bytes memory`.
    function _delegationDesignator(bytes memory code) internal pure returns (address) {
        if (code.length != DESIGNATOR_LENGTH) return address(0);

        bytes32 word;
        assembly ("memory-safe") {
            word := mload(add(code, 0x20))
        }

        uint256 prefixBits = 256 - PREFIX_LENGTH * 8;
        uint256 wordPrefix = uint256(word) >> prefixBits;
        if (wordPrefix != uint256(bytes32(DELEGATION_PREFIX)) >> prefixBits) return address(0);
        return address(uint160(uint256(word) >> (256 - DESIGNATOR_LENGTH * 8)));
    }
}
