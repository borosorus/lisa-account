// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal external boundary between clients and a LISA-enabled account.
/// @dev The concrete account will bind to a deployed LISA runtime address.
///      This interface intentionally does not describe the runtime itself: LISA
///      consumes the program as raw calldata through a low-level delegate call.
interface ILisaAccount {
    /// @notice LISA runtime used by this account implementation.
    function lisaRuntime() external view returns (address);

    /// @notice Execute an encoded LISA program through the account.
    /// @dev Authorization and delegate-call policy belong to the account
    ///      implementation and are intentionally unspecified here.
    function executeLisa(bytes calldata program) external payable;
}
