import 'package:flutter_test/flutter_test.dart';
import '../models/crypto_token.dart';
import 'token_preferences.dart';

void main() {
  group('TokenPreferences Tests', () {
    late TokenPreferences tokenPreferences;
    late List<CryptoToken> testTokens;

    setUp(() {
      tokenPreferences = TokenPreferences(userId: 'test_user');
      testTokens = [
        const CryptoToken(
          name: 'Bitcoin',
          symbol: 'BTC',
          blockchainName: 'Bitcoin',
          iconUrl: 'assets/images/btc.png',
          isEnabled: true,
          amount: 0.5,
          isToken: false,
        ),
        const CryptoToken(
          name: 'Ethereum',
          symbol: 'ETH',
          blockchainName: 'Ethereum',
          iconUrl: 'assets/images/ethereum_logo.png',
          isEnabled: true,
          amount: 2.0,
          isToken: false,
        ),
        const CryptoToken(
          name: 'Tether USD',
          symbol: 'USDT',
          blockchainName: 'Ethereum',
          iconUrl: 'assets/images/usdt.png',
          isEnabled: false,
          amount: 1000.0,
          isToken: true,
          smartContractAddress: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        ),
      ];
    });

    test('should generate correct token keys', () {
      final btcKey = tokenPreferences.getTokenKey(testTokens[0]);
      final ethKey = tokenPreferences.getTokenKey(testTokens[1]);
      final usdtKey = tokenPreferences.getTokenKey(testTokens[2]);

      expect(btcKey, 'BTC_Bitcoin_');
      expect(ethKey, 'ETH_Ethereum_');
      expect(usdtKey, 'USDT_Ethereum_0xdAC17F958D2ee523a2206206994597C13D831ec7');
    });

    test('should generate correct token keys from parameters', () {
      final key1 = tokenPreferences.getTokenKeyFromParams('BTC', 'Bitcoin', null);
      final key2 = tokenPreferences.getTokenKeyFromParams('USDT', 'Ethereum', '0x123');

      expect(key1, 'BTC_Bitcoin_');
      expect(key2, 'USDT_Ethereum_0x123');
    });

    test('should save and retrieve token order', () async {
      await tokenPreferences.initialize();
      
      final order = ['BTC_Bitcoin_', 'ETH_Ethereum_', 'USDT_Ethereum_0x123'];
      await tokenPreferences.saveTokenOrder(order);
      
      final retrievedOrder = tokenPreferences.getTokenOrder();
      expect(retrievedOrder, order);
    });

    test('should save and retrieve token states', () async {
      await tokenPreferences.initialize();
      
      // Test with CryptoToken
      await tokenPreferences.saveTokenStateFromToken(testTokens[0], true);
      await tokenPreferences.saveTokenStateFromToken(testTokens[1], false);
      
      expect(tokenPreferences.getTokenStateFromToken(testTokens[0]), true);
      expect(tokenPreferences.getTokenStateFromToken(testTokens[1]), false);
      
      // Test with parameters
      await tokenPreferences.saveTokenStateFromParams('BTC', 'Bitcoin', null, true);
      expect(tokenPreferences.getTokenStateFromParams('BTC', 'Bitcoin', null), true);
    });

    test('should get all enabled token keys', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.saveTokenStateFromToken(testTokens[0], true);
      await tokenPreferences.saveTokenStateFromToken(testTokens[1], false);
      await tokenPreferences.saveTokenStateFromToken(testTokens[2], true);
      
      final enabledKeys = tokenPreferences.getAllEnabledTokenKeys();
      expect(enabledKeys.length, 2);
      expect(enabledKeys, contains(tokenPreferences.getTokenKey(testTokens[0])));
      expect(enabledKeys, contains(tokenPreferences.getTokenKey(testTokens[2])));
    });

    test('should get all enabled tokens from list', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.saveTokenStateFromToken(testTokens[0], true);
      await tokenPreferences.saveTokenStateFromToken(testTokens[1], false);
      await tokenPreferences.saveTokenStateFromToken(testTokens[2], true);
      
      final enabledTokens = tokenPreferences.getAllEnabledTokens(testTokens);
      expect(enabledTokens.length, 2);
      expect(enabledTokens, contains(testTokens[0]));
      expect(enabledTokens, contains(testTokens[2]));
      expect(enabledTokens, isNot(contains(testTokens[1])));
    });

    test('should enable and disable tokens', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.enableToken(testTokens[0]);
      expect(tokenPreferences.isTokenEnabled(testTokens[0]), true);
      
      await tokenPreferences.disableToken(testTokens[0]);
      expect(tokenPreferences.isTokenEnabled(testTokens[0]), false);
    });

    test('should toggle token state', () async {
      await tokenPreferences.initialize();
      
      expect(tokenPreferences.isTokenEnabled(testTokens[0]), false);
      
      await tokenPreferences.toggleTokenState(testTokens[0]);
      expect(tokenPreferences.isTokenEnabled(testTokens[0]), true);
      
      await tokenPreferences.toggleTokenState(testTokens[0]);
      expect(tokenPreferences.isTokenEnabled(testTokens[0]), false);
    });

    test('should get enabled token count', () async {
      await tokenPreferences.initialize();
      
      expect(tokenPreferences.getEnabledTokenCount(), 0);
      
      await tokenPreferences.enableToken(testTokens[0]);
      await tokenPreferences.enableToken(testTokens[1]);
      
      expect(tokenPreferences.getEnabledTokenCount(), 2);
    });

    test('should get enabled tokens by blockchain', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.enableToken(testTokens[0]); // Bitcoin
      await tokenPreferences.enableToken(testTokens[1]); // Ethereum
      await tokenPreferences.enableToken(testTokens[2]); // Ethereum
      
      final ethereumTokens = tokenPreferences.getEnabledTokensByBlockchain(testTokens, 'Ethereum');
      expect(ethereumTokens.length, 2);
      expect(ethereumTokens.every((token) => token.blockchainName == 'Ethereum'), true);
    });

    test('should save and retrieve token order from tokens', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.saveTokenOrderFromTokens(testTokens);
      final orderedTokens = tokenPreferences.getTokenOrderAsTokens(testTokens);
      
      expect(orderedTokens.length, testTokens.length);
    });

    test('should update multiple token states', () async {
      await tokenPreferences.initialize();
      
      final tokenStates = {
        testTokens[0]: true,
        testTokens[1]: false,
        testTokens[2]: true,
      };
      
      await tokenPreferences.updateMultipleTokenStates(tokenStates);
      
      expect(tokenPreferences.isTokenEnabled(testTokens[0]), true);
      expect(tokenPreferences.isTokenEnabled(testTokens[1]), false);
      expect(tokenPreferences.isTokenEnabled(testTokens[2]), true);
    });

    test('should get token statistics', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.enableToken(testTokens[0]);
      await tokenPreferences.enableToken(testTokens[1]);
      
      final stats = tokenPreferences.getTokenStatistics(testTokens);
      
      expect(stats['totalTokens'], 3);
      expect(stats['enabledTokens'], 2);
      expect(stats['disabledTokens'], 1);
      expect(stats['enabledPercentage'], 66.7);
      expect(stats['blockchainDistribution']['Bitcoin'], 1);
      expect(stats['blockchainDistribution']['Ethereum'], 1);
    });

    test('should clear all token preferences', () async {
      await tokenPreferences.initialize();
      
      await tokenPreferences.enableToken(testTokens[0]);
      await tokenPreferences.saveTokenOrder(['BTC_Bitcoin_']);
      
      expect(tokenPreferences.getEnabledTokenCount(), 1);
      expect(tokenPreferences.getTokenOrder().isNotEmpty, true);
      
      await tokenPreferences.clearAllTokenPreferences();
      
      expect(tokenPreferences.getEnabledTokenCount(), 0);
      expect(tokenPreferences.getTokenOrder().isEmpty, true);
    });
  });
} 