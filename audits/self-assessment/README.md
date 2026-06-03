# Self-Assessment — CoinCeeper Wallet

This directory contains internal security self-assessments performed by the CoinCeeper development team. These are **not** a substitute for a professional external audit but serve as a baseline security review and documentation of our security posture.

## Completed Assessments

| Document | Status | Date |
|----------|--------|------|
| Cryptographic Review | ✅ Complete | June 2026 |
| Secure Storage Review | ✅ Complete | June 2026 |

## Self-Assessment Methodology

Each assessment follows a structured approach:

1. **Code Review** — Manual inspection of the relevant source files
2. **Test Verification** — Run existing unit tests and verify coverage
3. **Threat Modeling** — Identify potential attack vectors
4. **Best Practices Checklist** — Compare against industry standards
5. **Findings Documentation** — Record any issues and mitigations

## Key Security Principles Verified

- ✅ Private keys never leave the device
- ✅ Mnemonics are encrypted at rest (AES-256-GCM)
- ✅ Passcode uses PBKDF2 with 120,000 iterations
- ✅ All derivation uses standard BIP paths
- ✅ Trust Wallet Core is used as primary signing engine
- ✅ Pure Dart fallback exists for cross-platform compatibility
- ✅ Biometric authentication gates key access
- ✅ No API keys are hardcoded in the source
- ✅ All secrets are injected via `--dart-define` at build time
