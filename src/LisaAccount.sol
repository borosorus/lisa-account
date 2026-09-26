// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {SignerEIP7702} from "@openzeppelin/contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {ILisaAccount} from "./interfaces/ILisaAccount.sol";

/// @notice Composition scaffold for the future LISA EIP-7702 account.
/// @dev No account behavior is implemented yet. Keeping this abstract makes
///      the intended OpenZeppelin primitives and client interface compile-time
///      checked without prematurely choosing authorization or execution policy.
abstract contract LisaAccount is
    Account,
    SignerEIP7702,
    ERC7821,
    ERC721Holder,
    ERC1155Holder,
    ILisaAccount
{}
