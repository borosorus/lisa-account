// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Points an EOA at a LisaAccount implementation through an EIP-7702 delegation.
/// @dev The signing account is whatever Forge was given to broadcast with, exactly as in
///      `DeployLisaAccount.s.sol`: `--private-key`, `--keystore`, or the `--interactive` prompt. No
///      key is read from the environment and the script never holds one: it asks Forge's signer to
///      sign the authorization. That authorization rides on a transaction the EOA sends to itself, so
///      no third party ever holds the delegation, and it is chain-scoped, so it cannot be replayed on
///      another chain.
contract SetDelegation is Script {
    /// @notice LisaAccount implementation deployed on Ethereum Mainnet (see README).
    address internal constant DEFAULT_DELEGATION_TARGET = 0xE702F9FB288Bb97d359DA5eCB42532EAC6078871;

    /// @notice EIP-7702 delegation designator prefix, followed by a 20-byte address.
    bytes3 internal constant DELEGATION_PREFIX = 0xef0100;

    /// @notice EIP-7702 prefix of the authorization signing payload.
    bytes1 private constant AUTHORIZATION_MAGIC = hex"05";

    uint256 private constant PREFIX_LENGTH = 3;
    uint256 private constant DESIGNATOR_LENGTH = PREFIX_LENGTH + 20;

    /// @notice The script needs exactly one account to broadcast and sign with.
    error NoSigningAccount(uint256 available);

    /// @notice The EOA already delegates to another implementation.
    error AlreadyDelegated(address account, address current);

    /// @notice The EOA is an account whose code is not an EIP-7702 delegation.
    error UnexpectedCode(address account, uint256 codeLength);

    /// @notice The target is unusable as a delegation designator.
    error InvalidTarget(address target, address account);

    /// @notice The chain id does not fit the 64-bit authorization field, so no digest can be built.
    error ChainIdTooLarge(uint256 chainId);

    /// @notice The transaction carrying the authorization reverted.
    error DelegationTransactionFailed(address account, address target);

    function run() external returns (address account) {
        address target = vm.envOr("DELEGATION_TARGET", DEFAULT_DELEGATION_TARGET);
        account = _account();

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

        // EIP-7702 needs the authorization to carry the nonce the account will hold once the
        // transaction has spent its own.
        uint64 nonce = uint64(vm.getNonce(account) + 1);

        console.log("setting EIP-7702 delegation");
        console.log("  account:             %s", vm.toString(account));
        console.log("  target:              %s", vm.toString(target));
        console.log("  chain id:            %s", vm.toString(block.chainid));
        console.log("  authorization nonce: %s", vm.toString(uint256(nonce)));
        // An offline dry run has no state, so a zero size there is expected, not a verdict.
        console.log("  target code size:    %s", vm.toString(target.code.length));

        vm.startBroadcast();
        vm.attachDelegation(_authorize(target, nonce));

        // The empty self-call is what the authorization rides on. It doubles as a smoke test: if the
        // delegated code rejects an empty call, the whole transaction reverts, so the delegation does
        // not stick either.
        (bool executed,) = account.call("");
        if (!executed) revert DelegationTransactionFailed(account, target);
        vm.stopBroadcast();
    }

    /// @dev The account Forge broadcasts from. Virtual so a test can drive `run()`: tests have no
    ///      signing account, which is what `vm.getWallets` reports here.
    function _account() internal view virtual returns (address) {
        address[] memory wallets = vm.getWallets();
        if (wallets.length != 1) revert NoSigningAccount(wallets.length);
        return wallets[0];
    }

    /// @dev Signs the authorization for `implementation` with the script's signing account.
    function _authorize(address implementation, uint64 nonce)
        private
        view
        returns (Vm.SignedDelegation memory authorization)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_authorizationDigest(implementation, nonce));
        // `vm.sign` returns the legacy 27/28 offset; an authorization carries the raw y-parity.
        (authorization.v, authorization.r, authorization.s) = (v - 27, r, s);
        authorization.nonce = nonce;
        authorization.implementation = implementation;
    }

    /// @dev `keccak256(0x05 || rlp([chain_id, implementation, nonce]))`, the EIP-7702 signing payload.
    function _authorizationDigest(address implementation, uint64 nonce) internal view returns (bytes32) {
        if (block.chainid > type(uint64).max) revert ChainIdTooLarge(block.chainid);

        bytes memory items =
            bytes.concat(_scalar(uint64(block.chainid)), hex"94", bytes20(implementation), _scalar(nonce));
        // Both scalars are 64-bit, so the payload is at most 39 bytes and the short list header always
        // applies. Asserted rather than assumed, because a wrong header is a silently wrong digest.
        assert(items.length < 56);

        return keccak256(bytes.concat(AUTHORIZATION_MAGIC, bytes1(uint8(0xc0 + items.length)), items));
    }

    /// @dev Minimal big-endian RLP scalar: no leading zeros, and a bare byte below 0x80.
    function _scalar(uint64 value) private pure returns (bytes memory) {
        if (value == 0) return hex"80";

        uint256 length;
        for (uint64 shifted = value; shifted > 0; shifted >>= 8) {
            ++length;
        }

        bytes memory encoded = new bytes(length);
        for (uint256 i; i < length; ++i) {
            encoded[length - 1 - i] = bytes1(uint8(value >> (8 * i)));
        }

        if (length == 1 && value < 0x80) return encoded;
        return bytes.concat(bytes1(uint8(0x80 + length)), encoded);
    }

    /// @dev Reads the designator out of `0xef0100 <address>` code, or returns zero if the code is not
    ///      a delegation indicator.
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
