import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/wallet/core/wallet_core_bootstrap.dart';
import 'package:my_flutter_app/wallet/derivation/multi_chain_deriver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await WalletCoreBootstrap.initialize();
  });

  test('derivation matches backend golden vectors when fixture present', () async {
    final fixture = File('test/fixtures/derivation_golden.json');
    if (!fixture.existsSync()) {
      fail(
        'Missing test/fixtures/derivation_golden.json — run: '
        'python3 "backend cc/scripts/export_derivation_golden.py"',
      );
    }
    final list = jsonDecode(fixture.readAsStringSync()) as List<dynamic>;
    const deriver = MultiChainDeriver();
    for (final entry in list) {
      final mnemonic = entry['mnemonic'] as String;
      final expected =
          (entry['addresses'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          k,
          (v as Map)['public_address'] as String,
        ),
      );
      final derived = await deriver.deriveAll(mnemonic);
      for (final chain in expected.keys) {
        final local = derived[chain]?.publicAddress;
        expect(local, isNotNull, reason: 'Missing chain $chain');
        expect(
          local!.toLowerCase(),
          expected[chain]!.toLowerCase(),
          reason: '$chain mismatch for mnemonic prefix ${mnemonic.substring(0, 12)}',
        );
      }
    }
  });
}
