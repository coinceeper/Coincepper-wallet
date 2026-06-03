# Audit Scope — CoinCeeper Wallet

## What This Audit Covers

CoinCeeper Wallet is a **non-custodial multi-chain cryptocurrency wallet** built with Flutter. Unlike DeFi protocols or smart contract platforms, there are no on-chain contracts to audit. The security audit scope covers the **client-side application code** and its **cryptographic operations**.

### In Scope

| Component | Location | Description |
|-----------|----------|-------------|
| **BIP39 Mnemonic Generation** | `lib/wallet/wallet_repository.dart` | 12/24-word mnemonic generation using `bip39` package |
| **HD Key Derivation** | `lib/wallet/derivation/` | BIP32/BIP44/BIP84 key derivation for 10 blockchains |
| **Address Encoding** | `lib/wallet/derivation/chain_address_codec.dart` | Address format encoding per chain |
| **Transaction Signing** | `lib/wallet/transactions/signers/` | Local transaction signing (Trust Wallet Core + Dart fallback) |
| **Secure Key Storage** | `lib/wallet/keys/secure_key_vault.dart` | Biometric-gated mnemonic retrieval |
| **Encryption Engine** | `lib/services/wallet_crypto.dart` | AES-256-GCM with PBKDF2 key derivation |
| **Platform Storage** | `lib/services/secure_storage.dart` | FlutterSecureStorage wrapper |
| **API Communication** | `lib/services/api_service.dart` | Server communication (no private keys transmitted) |
| **TSP Agent** | `lib/services/tsp_agent_bootstrap.dart` | Background agent key management |

### Out of Scope

| Component | Reason |
|-----------|--------|
| **Backend servers** | Private infrastructure (separate security policy) |
| **Third-party RPC providers** | External services (Infura, Alchemy, dRPC, etc.) |
| **Operating system security** | Platform-level (Android/iOS) security is assumed |
| **Physical device security** | User's device security is out of our control |
| **Social engineering** | User-facing phishing prevention |
| **Smart contracts** | No smart contracts are deployed by the wallet |

## Supported Blockchains (Derivation Scope)

| Blockchain | Derivation Path | Standard |
|-----------|----------------|----------|
| Bitcoin | `m/84'/0'/0'/0/0` | BIP84 (Native SegWit) |
| Ethereum | `m/44'/60'/0'/0/0` | BIP44 |
| Binance Smart Chain | `m/44'/60'/0'/0/0` | BIP44 |
| Polygon | `m/44'/60'/0'/0/0` | BIP44 |
| Avalanche C-Chain | `m/44'/60'/0'/0/0` | BIP44 |
| Arbitrum | `m/44'/60'/0'/0/0` | BIP44 |
| Tron | `m/44'/195'/0'/0/0` | BIP44 |
| Solana | `m/44'/501'/0'/0'` | BIP44 (ed25519) |
| XRP | `m/44'/144'/0'/0/0` | BIP44 |
| Polkadot | `m/44'/354'/0'/0/0` | BIP44 (ed25519) |

## Existing Test Coverage

| Test File | Coverage |
|-----------|----------|
| `test/derivation_parity_test.dart` | Verifies address derivation against BIP39 golden vectors for all 10 chains |
| `test/wallet_crypto_test.dart` | AES-256-GCM encryption/decryption, passcode hashing |
| `test/wallet_secrets_migration_test.dart` | Secure storage migration safety |
| `test/wallet_core_smoke_test.dart` | Trust Wallet Core bindings initialization |
| `test/session_lock_coordinator_test.dart` | Session lock and timeout behavior |

## Verification Methodology

For a non-custodial wallet, the critical verification steps are:

1. **Derivation Correctness**: Feed known BIP39 mnemonics → verify expected addresses match
2. **Signing Correctness**: Sign known transactions → verify expected signatures
3. **Key Separation**: Verify private keys never appear in logs, network traffic, or UI
4. **Storage Security**: Verify mnemonic is encrypted at rest with AES-256-GCM
5. **Supply Chain**: Verify dependency hashes match expected values (supply chain integrity)

## Getting Started for Auditors

```bash
# Clone the repository
git clone git@github.com:coinceeper/Coincepper-wallet.git
cd Coincepper-wallet

# Install dependencies
flutter pub get

# Run existing tests
flutter test

# Run specific audit-relevant tests
flutter test test/derivation_parity_test.dart
flutter test test/wallet_crypto_test.dart

# Build for analysis
flutter build apk --debug
```

## Contact

For audit-related inquiries: **security@coinceeper.com**
