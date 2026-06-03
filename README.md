# CoinCeeper Wallet

**A decentralized, non-custodial cryptocurrency wallet built with Flutter.**

![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20macOS%20%7C%20Windows-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Flutter](https://img.shields.io/badge/Flutter-3.2%2B-blue)
[![derivation-parity](https://github.com/coinceeper/Coincepper-wallet/actions/workflows/derivation-parity.yml/badge.svg)](https://github.com/coinceeper/Coincepper-wallet/actions/workflows/derivation-parity.yml)
[![wallet-security](https://github.com/coinceeper/Coincepper-wallet/actions/workflows/wallet-security.yml/badge.svg)](https://github.com/coinceeper/Coincepper-wallet/actions/workflows/wallet-security.yml)

---

## ⚠️ Disclaimer

**THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.** The CoinCeeper team shall not be held liable for any claims, damages, or other liabilities arising from the use of this software. Cryptocurrency wallets involve significant financial risk. Use at your own risk. Always verify transactions before signing. Never share your seed phrase or private keys with anyone.

---

## Overview

CoinCeeper is a **self-custodial (non-custodial)** multi-chain cryptocurrency wallet. Your private keys never leave your device. All wallet creation, key derivation, transaction signing, and balance queries happen **locally on your device**.

### Supported Blockchains

| Blockchain | BIP Standard | Address Type |
|-----------|-------------|-------------|
| Bitcoin | BIP84 (Native SegWit) | bc1q... |
| Ethereum | BIP44 (m/44'/60') | 0x... |
| Binance Smart Chain | BIP44 (m/44'/60') | 0x... |
| Polygon | BIP44 (m/44'/60') | 0x... |
| Avalanche C-Chain | BIP44 (m/44'/60') | 0x... |
| Arbitrum | BIP44 (m/44'/60') | 0x... |
| Tron | BIP44 (m/44'/195') | T... |
| Solana | BIP44 (ed25519) | Base58 |
| XRP | BIP44 (m/44'/144') | r... |
| Polkadot | BIP44 (ed25519) | SS58 |

### Key Features

- **Non-Custodial**: Private keys generated and stored locally using secure platform storage (Android Keystore / iOS Keychain)
- **HD Wallet**: BIP39 mnemonic + BIP32/BIP44/BIP84 key derivation
- **Multi-Chain**: 10 blockchain networks supported
- **Offline Signing**: All transaction signing happens on-device
- **Secure Storage**: Passcode + biometric (Face ID / fingerprint) protection
- **Push Notifications**: Real-time transaction alerts
- **Built-in DEX**: Token swaps via integrated DEX services
- **Price Charts**: Real-time price data and historical charts
- **Multi-Language**: Farsi, English, Arabic, Turkish, Spanish, Chinese, and more

---

## Architecture

```
CoinCeeper Wallet
├── lib/
│   ├── wallet/              # Core wallet logic (BIP39, HD derivation, signing)
│   │   ├── derivation/      # BIP32/BIP44/BIP84 key derivation (pure Dart + WC Core)
│   │   ├── transactions/    # Offline transaction signing
│   │   ├── history/         # On-chain history indexers
│   │   ├── core/            # Wallet Core bootstrap & config
│   │   └── keys/            # Secure key vault
│   ├── services/            # API, storage, notifications, security
│   ├── screens/             # UI screens
│   ├── providers/           # State management (Provider)
│   ├── navigation/          # GoRouter-based navigation
│   ├── widgets/             # Reusable UI components
│   ├── ui/                  # Design system components
│   └── theme/               # Theming & styling
├── test/                    # Unit & golden tests
├── android/                 # Native Android (Kotlin)
├── ios/                     # Native iOS (Swift/ObjC)
├── scripts/                 # Build & utility scripts
└── assets/                  # Images, translations, configs
```

### Security Architecture

1. **Wallet Creation**: Uses `bip39` package for mnemonic generation (12/24 words). Keys derived using BIP32/BIP44/BIP84 with both Trust Wallet Core (native bindings) and a pure-Dart fallback.

2. **Key Storage**: Mnemonics stored in `FlutterSecureStorage` (backed by Android Keystore / iOS Keychain). Passcode protection with PBKDF2 (120K iterations) + AES-256-GCM encryption.

3. **Transaction Signing**: All signing happens on-device using native Trust Wallet Core bindings or pure-Dart signers. Private keys never leave the device.

4. **API Layer**: The app communicates with a public cache proxy for price data, chart data, and push notifications. No user private keys or seed phrases are ever transmitted to any server.

---

## Getting Started

### Prerequisites

- Flutter SDK >= 3.2.3
- Dart SDK >= 3.2.3
- Android Studio / Xcode (for platform builds)
- Rust toolchain (for Trust Wallet Core bindings, optional)

### Installation

```bash
# Clone the repository
git clone git@github.com:coinceeper/Coincepper-wallet.git
cd Coincepper-wallet

# Install dependencies
flutter pub get

# Run in debug mode (with default dev secrets)
flutter run
```

### Environment Configuration

The app requires certain API keys for full functionality. Copy the example file and fill in your keys:

```bash
# Copy the example env file
cp .env.example .env
# Or use the helper script
powershell -File scripts/run_with_keys.ps1
```

For release builds, you must provide these as `--dart-define` arguments:

```bash
flutter run --dart-define=ETHERSCAN_API_KEY=YOUR_KEY --dart-define=CLIENT_HMAC_SECRET=YOUR_SECRET
```

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test suites
flutter test test/derivation_parity_test.dart
flutter test test/wallet_crypto_test.dart
flutter test test/wallet_secrets_migration_test.dart
```

---

## Reproducible Builds

To verify that the app binary matches this source code:

1. Check out the exact tagged commit
2. Build with the same Flutter version
3. Compare the SHA-256 hash of the output APK/IPA

We aim to provide reproducible build documentation and scripts in a future release.

---

## Contributing

Contributions are welcome! Please ensure:

1. No secrets or API keys are committed
2. All sensitive configuration uses `--dart-define` or environment variables
3. Tests pass before submitting PRs
4. The derivation parity test continues to pass for all supported chains

---

## Security Audits

We are committed to transparency. Once security audits are completed by reputable firms (such as CertiK, Hacken, or Quantstamp), the full audit reports will be published here.

### Reporting Vulnerabilities

If you discover a security vulnerability, please DO NOT file a public issue. Instead, contact us privately at security@coinceeper.com.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Open Source Attribution

CoinCeeper Wallet uses several open-source components:

- [Trust Wallet Core](https://github.com/trustwallet/wallet-core) — HD wallet & signing
- [Flutter](https://flutter.dev/) — UI framework
- [Go Router](https://pub.dev/packages/go_router) — Navigation
- [web3dart](https://pub.dev/packages/web3dart) — Ethereum interaction
- [BIP39](https://pub.dev/packages/bip39) — Mnemonic generation
- [Pointy Castle](https://pub.dev/packages/pointycastle) — Cryptographic primitives
