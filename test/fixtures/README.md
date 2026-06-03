# Derivation golden vectors

Generate with:

```bash
cd "backend cc"
pip install -r requirements.txt
python3 scripts/export_derivation_golden.py
```

Output: `test/fixtures/derivation_golden.json`

Run parity test:

```bash
flutter test test/derivation_parity_test.dart
```

## EVM transaction history

Set an Etherscan-class API key at build time:

```bash
flutter run --dart-define=ETHERSCAN_API_KEY=your_key_here
flutter test --dart-define=ETHERSCAN_API_KEY=your_key_here
```
