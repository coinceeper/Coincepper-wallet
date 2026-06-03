# Security Audits — CoinCeeper Wallet

This directory contains all security audit-related documentation, self-assessments, scope definitions, grant applications, and future external audit reports for the CoinCeeper Wallet.

## Audit Philosophy

CoinCeeper Wallet is a **non-custodial client-side application** — there are no smart contracts to audit. The security model relies on:

1. **Proven cryptographic libraries** (Trust Wallet Core, bip39, bip32, AES-256-GCM)
2. **Platform-native secure storage** (Android Keystore / iOS Keychain)
3. **Local-only signing** (private keys never leave the device)
4. **Test-verified derivation** (BIP39 golden vector tests)

Because this is a client-side mobile wallet (Flutter), traditional "smart contract audits" do not apply. Instead, the relevant security assessments are:

- **Cryptographic implementation review** — correct BIP39/BIP32/BIP44/BIP84 derivation
- **Secure storage analysis** — platform keystore integration and encryption
- **Penetration testing** — mobile app attack surface assessment
- **Supply chain review** — dependency integrity verification

## Current Status

| Area | Status | Date |
|------|--------|------|
| BIP39 Derivation Parity Tests | ✅ Passed | June 2026 |
| Wallet Crypto (AES-256-GCM) Tests | ✅ Passed | June 2026 |
| Secrets Migration Tests | ✅ Passed | June 2026 |
| Secure Storage Review | ✅ Complete | June 2026 |
| Cryptographic Review | ✅ Complete | June 2026 |
| External Security Audit | ❌ Not yet performed | — |

## Directory Structure

```
audits/
├── README.md                          # This file
├── SCOPE.md                           # Audit scope definition
├── self-assessment/
│   ├── README.md                      # Self-assessment overview
│   ├── cryptographic-review.md        # BIP39/BIP32/key derivation review
│   └── secure-storage-review.md       # Secure storage & encryption review
├── grants/
│   └── README.md                      # Grant & funding opportunities
└── reports/                           # External audit reports (future)
    └── .gitkeep
```

## Planned External Audits

We are committed to undergoing professional security audits from reputable firms. The following timeline is targeted:

1. **Self-assessment** — Complete internal security review (Q2 2026)
2. **Grant applications** — Apply for audit subsidy programs (Q2-Q3 2026)
3. **External audit** — Engage with a vetted security firm (Q3-Q4 2026)
4. **Remediation** — Address findings and re-audit (Q4 2026)
5. **Publication** — Publish full audit reports here (Q4 2026)

## Target Audit Firms

| Firm | Specialty | Website |
|------|-----------|---------|
| Trail of Bits | Application security, crypto | trailofbits.com |
| Kudelski Security | Mobile app security, cryptography | kudelskisecurity.com |
| Hacken | Smart contracts + applications | hacken.io |
| Quantstamp | Full-stack security | quantstamp.com |
| CertiK | End-to-end verification | certik.com |

> **Note**: For a client-side Flutter wallet without smart contracts, the most value comes from firms with **mobile application security** and **cryptographic implementation** expertise, rather than pure smart contract auditors.

## Vulnerability Disclosure

If you discover a security vulnerability, please **do NOT file a public issue**.  
Report it privately to **security@coinceeper.com** with details.

See [SECURITY.md](../SECURITY.md) for our full vulnerability disclosure policy.
