// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LisaAccount} from "../src/LisaAccount.sol";

/// @notice Deployment scaffold. A concrete deployment script will be added
///         once LisaAccount has runtime binding and authorization semantics.
abstract contract DeployLisaAccountScript is Script {}
