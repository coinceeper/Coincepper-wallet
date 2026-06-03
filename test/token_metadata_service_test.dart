import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_flutter_app/wallet/tokens/token_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenMetadataService', () {
    test('native token uses chain decimals', () async {
      final d = await TokenMetadataService.instance.decimalsForToken(
        blockchainName: 'Bitcoin',
        contractAddress: '',
        symbol: 'BTC',
      );
      expect(d, 8);
    });

    test('fallback decimals for stablecoins', () async {
      SharedPreferences.setMockInitialValues({});
      final d = await TokenMetadataService.instance.decimalsForToken(
        blockchainName: 'Ethereum',
        contractAddress: '0x000000000000000000000000000000000000dead',
        symbol: 'USDT',
      );
      expect(d, 6);
    });

    test('disk cache is reused within TTL', () async {
      SharedPreferences.setMockInitialValues({});
      const key = 'ethereum:0xabc';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'token_decimals_$key',
        jsonEncode({
          'decimals': 9,
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      final d = await TokenMetadataService.instance.decimalsForToken(
        blockchainName: 'Ethereum',
        contractAddress: '0xAbC',
        symbol: 'TEST',
      );
      expect(d, 9);
    });
  });
}
