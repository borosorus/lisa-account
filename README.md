# lisa-account

Smart-account infrastructure for using LISA through an EIP-7702 delegated account.

This repository is intentionally separate from the LISA VM/compiler implementation. The account will bind to a **deployed LISA runtime address**; it does not vendor or pin the `lisa-evm` repository.

## Intended boundary

```text
EOA
  │ EIP-7702 delegation
  ▼
LisaAccount
  │ authorization / account policy
  │
  └─ executeLisa(program)
         │ delegatecall
         ▼
     deployed LISA runtime
```

The account layer owns authorization and smart-account behavior. The LISA runtime owns VM execution semantics.

## Current status

This repository currently contains infrastructure only:

- OpenZeppelin smart-account / EIP-7702 imports;
- the minimal `ILisaAccount` integration interface;
- an abstract `LisaAccount` composition scaffold;
- deployment and test scaffolding;
- Foundry configuration and CI.

The actual account authorization, runtime binding, execution logic, and deployment flow are intentionally not implemented yet.

## Dependencies

- [forge-std](https://github.com/foundry-rs/forge-std)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)

OpenZeppelin Contracts is used for the account primitives (`Account`, `SignerEIP7702`, `ERC7821`, and token receiver helpers).

There is deliberately **no `lisa-evm` submodule**. A concrete account deployment will reference a deployed LISA runtime address instead.

## Commands

```bash
forge build
forge test
forge fmt --check
```

or:

```bash
make ci
```
