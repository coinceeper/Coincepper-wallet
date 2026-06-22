# CoinCeeper Wallet

**A decentralized, non-custodial cryptocurrency wallet built with Flutter.**

![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20macOS%20%7C%20Windows-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Flutter](https://img.shields.io/badge/Flutter-3.2%2B-blue)

---

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Testing](#testing)
- [Security](#security)
- [License](#license)
- [Support](#support)

---

## ⚠️ Disclaimer

**THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.** Cryptocurrency wallets involve significant financial risk. Use at your own risk. Always verify transactions before signing. Never share your seed phrase or private keys with anyone. The CoinCeeper team shall not be held liable for any claims, damages, or other liabilities arising from the use of this software.

---

## Overview

CoinCeeper is a self-custodial cryptocurrency wallet that puts you in full control of your digital assets. Your private keys never leave your device. All sensitive operations — key generation, transaction signing, and address derivation — happen locally, on-device.

**Key principles:**

- **Non-custodial**: You hold your keys. CoinCeeper never has access to your funds.
- **Open source**: The code is transparent and auditable by anyone.
- **Multi-chain**: Supports Bitcoin, Ethereum, Solana, TRON, and other networks.
- **Cross-platform**: Available on Android, iOS, Web, macOS, and Windows.

---

## Features

| Feature | Description |
|---|---|
| **BIP39 Seed Generation** | Cryptographically secure mnemonic phrases generated on-device |
| **HD Wallet (BIP32/BIP44/BIP84)** | Hierarchical deterministic key derivation for multiple chains |
| **Local Transaction Signing** | All transactions signed on-device; private keys never exposed |
| **Multi-chain Support** | Bitcoin, Ethereum & EVM chains, Solana, TRON, and more |
| **On-chain Balance Fetching** | Read-only queries to public RPC nodes — no intermediaries |
| **Secure Storage** | iOS Keychain / Android EncryptedSharedPreferences with biometric authentication |
| **Address Book** | Save and manage frequently used addresses locally |
| **Push Notifications** | Encrypted notifications via Firebase (no sensitive data transmitted) |
| **Portfolio Management** | Track balances, transaction history, and price charts |
| **QR Code Scanner** | Easy address entry and payment requests |
| **Price Alerts** | Configurable notifications for price movements |
| **Multi-language** | English, Farsi, Arabic, Turkish, Spanish, and more |
| **Biometric Auth** | Face ID, fingerprint, and passcode for secure app access |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  User Interface                      │
│         (Home, Send, Receive, Settings, etc.)        │
├─────────────────────────────────────────────────────┤
│                 View Models / Providers              │
├─────────────────────────────────────────────────────┤
│                   Domain Services                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────────┐ │
│  │ Wallet   │ │ Balance  │ │ Transaction          │ │
│  │ Service  │ │ Manager  │ │ Service              │ │
│  └────┬─────┘ └────┬─────┘ └──────────┬───────────┘ │
│       │            │                  │              │
├───────┴────────────┴──────────────────┴─────────────┤
│                 Wallet Core                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────────┐ │
│  │ Key      │ │ HD       │ │ Transaction          │ │
│  │ Vault    │ │ Deriver  │ │ Signer               │ │
│  └────┬─────┘ └────┬─────┘ └──────────┬───────────┘ │
│       │            │                  │              │
├───────┴────────────┴──────────────────┴─────────────┤
│                    Storage Layer                     │
│  ┌─────────────────────┐  ┌──────────────────────┐  │
│  │ iOS Keychain /      │  │ Secure                │  │
│  │ Android EncryptedSP │  │ Preferences           │  │
│  └─────────────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Key Security Boundaries

1. **Key Generation**: BIP39 mnemonics and BIP32 master seeds are generated entirely on-device using cryptographically secure random number generators. No seed data ever reaches any server.

2. **Key Storage**: Seeds and private keys are encrypted at rest using platform-native secure storage (iOS Keychain, Android EncryptedSharedPreferences). Access requires biometric authentication (Face ID / fingerprint) or passcode.

3. **Transaction Signing**: Raw transactions are constructed and signed locally using native wallet core libraries. The signed transaction bytes are broadcast to public RPC endpoints — no private keys are ever transmitted.

4. **Balance Queries**: Public addresses are derived locally and used to query on-chain data via public RPC nodes (Infura, Alchemy, public Solana RPC, etc.).

5. **Server Role**: The server acts as a cache proxy for public data (prices, charts) and a notification relay. It never receives or stores any private keys, mnemonics, or transaction signing requests.

---

## Getting Started

### Prerequisites

- Flutter SDK 3.2+
- Dart SDK 3.0+
- Platform-specific toolchains (Xcode for iOS/macOS, Android Studio for Android)

### Setup

```bash
# Clone the repository
git clone https://github.com/coinceeper/Coincepper-wallet.git
cd Coincepper-wallet

# Install dependencies
flutter pub get

# Run in debug mode
flutter run
```

### Build Release

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

> **Note**: Build-time secrets (API keys, server URLs) are passed via `--dart-define`. You will need to provide your own keys for certain features. See the build configuration files for the complete list of required defines.

---

## Project Structure

```
lib/
├── main.dart              # Application entry point
├── screens/               # UI screens (Home, Send, Receive, Settings, etc.)
├── providers/             # State management (ChangeNotifier providers)
├── services/              # Business logic and external service integrations
├── wallet/                # Core wallet operations
│   ├── keys/              # Key generation and secure key vault
│   ├── derivation/        # HD wallet derivation (BIP32/BIP44/BIP84)
│   ├── transactions/      # Transaction construction and signing
│   ├── history/           # On-chain transaction history indexing
│   └── core/              # Wallet bootstrap and core bridge
├── models/                # Data models
├── navigation/            # Routing and navigation
├── widgets/               # Reusable UI components
├── theme/                 # App theming
└── utils/                 # Utility functions
```

---

## Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/wallet/derivation_test.dart
```

---

## Security

### Non-Custodial Verification

CoinCeeper is a non-custodial wallet. To verify this independently:

1. **Audit the key generation code** at `lib/wallet/keys/`
2. **Audit the derivation code** at `lib/wallet/derivation/`
3. **Audit the signing code** at `lib/wallet/transactions/signers/`
4. **Audit the storage layer** at `lib/services/secure_storage.dart`
5. **Build from source** and verify it connects only to public RPC endpoints

### Reporting Vulnerabilities

Please report security vulnerabilities to **security@coinceeper.com**. We take all security reports seriously and will respond promptly.

---

## License

```
MIT License

Copyright (c) 2024 CoinCeeper

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Support

- **Issues**: [GitHub Issues](https://github.com/coinceeper/Coincepper-wallet/issues)
- **Security**: security@coinceeper.com
