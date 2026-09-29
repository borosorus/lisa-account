// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SignerEIP7702} from "@openzeppelin/contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {ILisaAccount} from "./interfaces/ILisaAccount.sol";

/// @notice Minimal EIP-7702 account with standard batching and LISA execution.
/// @dev The contract is intentionally stateless. A deployment is permanently
///      bound to one deployed LISA runtime through an immutable address.
contract LisaAccount is Account, SignerEIP7702, ERC7821, ERC721Holder, ERC1155Holder, ILisaAccount, IERC1271 {
    address private immutable _lisaRuntime;

    constructor(address lisaRuntime_) {
        if (lisaRuntime_.code.length == 0) revert Address.AddressEmptyCode(lisaRuntime_);
        _lisaRuntime = lisaRuntime_;
    }

    /// @inheritdoc ILisaAccount
    function lisaRuntime() public view override returns (address) {
        return _lisaRuntime;
    }

    /// @inheritdoc ILisaAccount
    function executeLisa(bytes calldata program) external payable override onlyEntryPointOrSelf {
        Address.functionDelegateCall(_lisaRuntime, program);
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        return _rawSignatureValidation(hash, signature) ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }

    /// @dev ERC-7821 remains self-authorized for direct EIP-7702 transactions
    ///      and also accepts execution from the canonical ERC-4337 EntryPoint.
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view override returns (bool) {
        return
            caller == address(entryPoint()) || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
