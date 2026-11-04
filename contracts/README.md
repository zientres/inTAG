# TagitalSpace — TON Testnet contracts

All deployment targets in this repository are **TON Testnet only**.

## Current implementation stage

- TEP-62 / TEP-64 NFT collection and NFT item reference implementation, written in Tolk.
- The collection's `adminAddress` is intentionally treated as the trusted Auction Manager address. It must not be set to an ordinary user's wallet in the final deployment.
- Royalty storage follows TEP-66. The planned creator royalty is 2% (numerator 2, denominator 100).
- The public auction flow and its manager are not yet implemented. Do not deploy the NFT collection by itself: doing so before the Auction Manager exists would leave mint authorization incorrectly configured.

## Project economics

Primary auction proceeds: 50% creator, 30% treasury, 20% development/security fund.
Secondary-market royalty: 2% to the creator, as advertised by TEP-66. TEP-66 is a royalty information standard; external marketplaces must choose to honor it.

## Testnet owner

Creator wallet (provided by the project owner):
`0QAlaQjrvRz8GCm2IJ1QXA6rNGSyyYfH6uNPT0RzKja6VsLi`

Treasury and development/security addresses are intentionally left unconfigured until supplied. Never put seed phrases or private keys in this repository.

## Build

Install Acton 1.2.0 and run:

```sh
acton build
```

The contracts must pass compilation and tests before deployment. The deploy transaction must be approved by the owner in their TON Testnet wallet.
