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

Deploy the LISA runtime first, then deploy the account implementation with that runtime address:

```bash
LISA_RUNTIME=0x... forge script script/DeployLisaAccount.s.sol:DeployLisaAccount --broadcast --rpc-url ...
```

A new LISA runtime version should normally correspond to a new account implementation deployment rather than mutating an existing binding.

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
