# Contributing to CoinCeeper Wallet

First off, thank you for considering contributing to CoinCeeper Wallet! We welcome contributions from the community.

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## How to Contribute

### Reporting Bugs

1. **Check existing issues** — see if the bug has already been reported
2. **Create a new issue** using the "Bug Report" template
3. **Include detailed information**:
   - Device model and OS version
   - Flutter version (`flutter --version`)
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots (if applicable)

### Feature Requests

1. **Check existing issues** — see if the feature has already been requested
2. **Create a new issue** using the "Feature Request" template
3. **Describe the feature** clearly, including:
   - Use case and motivation
   - How it should work
   - Any alternatives considered

### Pull Requests

1. **Fork the repository**
2. **Create a new branch** from `main`
3. **Make your changes**
4. **Run tests**: `flutter test`
5. **Commit** with clear messages
6. **Push to your fork** and submit a Pull Request

## Development Setup

```bash
flutter pub get
flutter test
flutter run --dart-define=ETHERSCAN_API_KEY=YOUR_KEY
```

## Security

**Never commit**: API keys, private keys, `.env` files, keystore files, or Firebase credentials.
All secrets must be passed via `--dart-define` at build time.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
