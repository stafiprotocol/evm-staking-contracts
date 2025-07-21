# EVM Staking Vault Contracts

A Staking Vault is a programmable smart contract module that enables users to stake tokens and accrue rewards. Vaults encapsulate all necessary staking logic for a specific token or chain, including:

- Staking and unstaking flow
- Reward calculation and distribution
- Interaction with native staking mechanisms

In the Vault-as-a-Service model, these vaults can be created and operated by third parties (e.g., token teams, DAOs, protocols), using StaFi’s secure and modular infrastructure.

## Structure

The contracts are developed using Foundry and adhere to the standard Foundry project structure.

All contracts are located in `contracts/` folder, tests in `test/` folder and deployment and other scripts in `script/` folder.

## Development

### Run test

```bash
forge test
```

## Deployment

### Deploy all contracts with ERC1967 Proxy 
```bash
export PRIVATE_KEY=0xXXXXX
forge script script/DeployStaking.s.sol --rpc-url https://ethereum-holesky-rpc.publicnode.com --broadcast
```

## License

The license for EVM Staking Vault Contracts is the Business Source License 1.1 (BUSL-1.1), see [LICENSE](./LICENSE).
