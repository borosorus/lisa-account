// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice LISA-specific surface of a delegated smart account.
/// @dev Standard account execution and signature interfaces are inherited
///      separately from OpenZeppelin.
interface ILisaAccount {
    /// @notice Immutable LISA runtime used by this account implementation.
    function lisaRuntime() external view returns (address);

    /// @notice Execute an encoded LISA program in the account's context.
    /// @dev Restricted by the account implementation to self or EntryPoint.
    function executeLisa(bytes calldata program) external payable;
}
