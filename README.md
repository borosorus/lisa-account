# lisa-account

Minimal smart-account infrastructure for using LISA through an EIP-7702 delegated account.

The account intentionally stays small and stateless. It provides standard account plumbing and delegates programmable execution to a separately deployed LISA runtime.

## Architecture

```text
EOA
  │ EIP-7702 delegation
  ▼
LisaAccount
  ├─ EOA signature authority (SignerEIP7702)
  ├─ ERC-1271 signature validation
  ├─ ERC-4337 account validation
  ├─ ERC-7821 atomic batch execution
  ├─ ERC-721 / ERC-1155 receiving
  └─ executeLisa(program)
         │ delegatecall
         ▼
     deployed LISA runtime
```

Each `LisaAccount` implementation is permanently bound to one deployed LISA runtime address through an immutable constructor argument. There is no runtime setter, generic delegatecall, owner storage, plugin system, or custom multicall.

For ordinary atomic batches, clients can use the inherited ERC-7821 `execute` function. For programmable execution, clients can use `executeLisa(bytes)`.

Both execution paths accept direct self-calls, as used by an EIP-7702 delegated EOA. ERC-7821 and LISA execution also accept the canonical ERC-4337 EntryPoint path provided by OpenZeppelin `Account`.

## Deployment

### Ethereum Mainnet

| Contract | Address |
| --- | --- |
| LisaAccount implementation | [`0xE702F9FB288Bb97d359DA5eCB42532EAC6078871`](https://etherscan.io/address/0xE702F9FB288Bb97d359DA5eCB42532EAC6078871) |
| Bound LISA runtime | [`0x7F6b058AAF78BC690f781F0914499C460Ff342D9`](https://etherscan.io/address/0x7F6b058AAF78BC690f781F0914499C460Ff342D9) |

Deployment transaction: [`0xb01c26e04ffd4afb8cdf72ee17518bcb4e744f29ebf2625f1d33fced38d55797`](https://etherscan.io/tx/0xb01c26e04ffd4afb8cdf72ee17518bcb4e744f29ebf2625f1d33fced38d55797).

### Sepolia

| Contract | Address |
| --- | --- |
| LisaAccount implementation | [`0x7f5F0a949f5F9Dc78d1F8e7F648Ec12AF24ADa82`](https://sepolia.etherscan.io/address/0x7f5F0a949f5F9Dc78d1F8e7F648Ec12AF24ADa82) |
| Bound LISA runtime | [`0x8f024da6317209Eb756f34D3D489A5b4de6152DC`](https://sepolia.etherscan.io/address/0x8f024da6317209Eb756f34D3D489A5b4de6152DC) |

Deployment transaction: [`0xdb7873c6a0c7bb2e5091439e91b9101de40244dc9e0a28cbb1d043d13813909c`](https://sepolia.etherscan.io/tx/0xdb7873c6a0c7bb2e5091439e91b9101de40244dc9e0a28cbb1d043d13813909c).

### Deploying another implementation

Deploy the LISA runtime first, then deploy the account implementation with that runtime address:

```bash
LISA_RUNTIME=0x... forge script script/DeployLisaAccount.s.sol:DeployLisaAccount --broadcast --rpc-url ...
```

A new LISA runtime version should normally correspond to a new account implementation deployment rather than mutating an existing binding.

## Setting the delegation

`script/SetDelegation.s.sol` points an EOA at an implementation. Give it the signing account the way you would for any Foundry script; the script itself never sees a key. It asks Forge's signer to sign the EIP-7702 authorization, and the EOA sends the resulting type-0x04 transaction to itself, so no third party ever holds the delegation:

```bash
forge script script/SetDelegation.s.sol --rpc-url <rpc-url> --broadcast --interactive

# or, without the prompt
forge script script/SetDelegation.s.sol --rpc-url <rpc-url> --broadcast \
  --keystore ~/.foundry/keystores/my-eoa
```

- The delegated account is the account Forge broadcasts from, so pass exactly one: `--interactive`, `--keystore`/`--account`, or `--private-key`. No `PRIVATE_KEY` environment variable is involved, and no key ever enters the script.
- `DELEGATION_TARGET` selects the implementation; it defaults to the mainnet deployment above. On Sepolia, set it to `0x7f5F0a949f5F9Dc78d1F8e7F648Ec12AF24ADa82`.
- The authorization is chain-scoped, so it cannot be replayed on another chain.
- The script is idempotent: it does nothing if the EOA already delegates to the target, and reverts with `AlreadyDelegated`, naming both addresses, rather than silently replacing a delegation that points somewhere else.
- Moving an account to a new implementation is out of scope here on purpose. EIP-7702 clears a delegation with an authorization that designates the zero address, and this script refuses to sign one, so re-pointing cannot happen by accident.
- Omit `--broadcast` for a dry run. `foundry.toml` pins `evm_version = "prague"` so Forge's EVM accepts the type-0x04 transaction; it does not change solc's codegen target, so the built bytecode still matches the deployed implementation.

## Dependencies

- [forge-std](https://github.com/foundry-rs/forge-std)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)

There is deliberately no `lisa-evm` source dependency or submodule. The integration boundary is the deployed runtime address.

## Development

```bash
forge fmt
forge build
forge test
```

or:

```bash
make ci
```

GitHub Actions runs formatting, build, and tests on pushes and pull requests.
