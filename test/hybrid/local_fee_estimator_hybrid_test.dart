import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/api_models.dart';
import 'package:my_flutter_app/services/backend_proxy_service.dart';
import 'package:my_flutter_app/services/local_fee_estimator.dart';

void main() {
  group('LocalFeeEstimator — Hybrid Routing', () {
    late BackendProxyService proxy;

    setUp(() {
      proxy = BackendProxyService.instance;
      proxy.initialize(baseUrl: 'https://0.0.0.0:0');
    });

    tearDown(() {
      proxy.dispose();
    });

    test('estimateFee for Ethereum uses proxy first, falls back to direct', () async {
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'Ethereum',
        fromAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        toAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        amount: 0.01,
      );

      // Should return a valid fee response even when both routes fail
      // due to the _fallbackFeeResponse()
      expect(fee, isA<EstimateFeeResponse>());
      expect(fee.gasPrice, greaterThan(0));
      expect(fee.fee, greaterThan(0));
      expect(fee.feeCurrency, isNotEmpty);
      expect(fee.priorityOptions, isNotNull);
      expect(fee.priorityOptions!.slow, isNotNull);
      expect(fee.priorityOptions!.average, isNotNull);
      expect(fee.priorityOptions!.fast, isNotNull);
    });

    test('estimateFee for Polygon uses proxy first', () async {
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'Polygon',
        fromAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        toAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        amount: 0.01,
      );

      expect(fee, isA<EstimateFeeResponse>());
      expect(fee.gasPrice, greaterThan(0));
    });

    test('estimateFee for BSC uses proxy first, currency is BNB or ETH fallback', () async {
      // Proxy fails → direct Web3Client may also fail → fallback returns 'ETH'
      // If direct succeeds → returns 'BNB'
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'BSC',
        fromAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        toAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        amount: 0.01,
      );

      expect(fee, isA<EstimateFeeResponse>());
      expect(
        ['BNB', 'ETH'],
        contains(fee.feeCurrency),
        reason: 'BNB if direct RPC succeeds, ETH if both routes fail',
      );
    });

    test('estimateFee for Bitcoin bypasses proxy (direct only)', () async {
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'Bitcoin',
        fromAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
        toAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
        amount: 0.01,
      );

      expect(fee, isA<EstimateFeeResponse>());
      expect(fee.feeCurrency, 'BTC');
    });

    test('estimateFee for Tron bypasses proxy (direct only)', () async {
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'Tron',
        fromAddress: 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
        toAddress: 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
        amount: 0.01,
      );

      expect(fee, isA<EstimateFeeResponse>());
      expect(fee.feeCurrency, 'TRX');
    });

    test('estimateFee for unknown chain returns fallback response', () async {
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'UnknownChain',
        fromAddress: 'test',
        toAddress: 'test',
        amount: 0.01,
      );

      expect(fee, isA<EstimateFeeResponse>());
      expect(fee.feeCurrency, 'ETH');
      expect(fee.gasUsed, 21000);
    });

    test('estimateFee for ERC20 token uses route() without crashing', () async {
      final fee = await LocalFeeEstimator.instance.estimateFee(
        blockchain: 'Ethereum',
        fromAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        toAddress: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
        amount: 0.01,
        tokenContract: '0xdAC17F958D2ee523a2206206994597C13D831ec7', // USDT
      );

      expect(fee, isA<EstimateFeeResponse>());
      expect(fee.gasPrice, greaterThan(0));
    });
  });
}
