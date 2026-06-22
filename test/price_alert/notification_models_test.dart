import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/models/notification_models.dart';

void main() {
  group('PriceAlertItem — Serialization', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 1,
        'symbol': 'BTC',
        'target_price': 75000.0,
        'alert_type': 'above',
        'target_percent': null,
        'reference_price': 70000.0,
        'is_active': true,
        'created_at': '2026-01-15T10:30:00Z',
      };

      final item = PriceAlertItem.fromJson(json);

      expect(item.id, 1);
      expect(item.symbol, 'BTC');
      expect(item.targetPrice, 75000.0);
      expect(item.alertType, 'above');
      expect(item.targetPercent, isNull);
      expect(item.referencePrice, 70000.0);
      expect(item.isActive, true);
      expect(item.createdAt, '2026-01-15T10:30:00Z');
    });

    test('fromJson handles null fields gracefully', () {
      final json = {
        'symbol': 'ETH',
        'alert_type': 'below',
      };

      final item = PriceAlertItem.fromJson(json);

      expect(item.id, isNull);
      expect(item.symbol, 'ETH');
      expect(item.targetPrice, isNull);
      expect(item.alertType, 'below');
      expect(item.targetPercent, isNull);
      expect(item.referencePrice, isNull);
      expect(item.isActive, true); // default
      expect(item.createdAt, isNull);
    });

    test('isPercentAlert returns true for percent types', () {
      const percentUp = PriceAlertItem(
        symbol: 'BTC', alertType: 'percent_up',
      );
      expect(percentUp.isPercentAlert, true);
      expect(percentUp.isPriceAlert, false);

      const percentDown = PriceAlertItem(
        symbol: 'BTC', alertType: 'percent_down',
      );
      expect(percentDown.isPercentAlert, true);
      expect(percentDown.isPriceAlert, false);
    });

    test('isPercentAlert returns false for price types', () {
      const above = PriceAlertItem(
        symbol: 'BTC', alertType: 'above',
      );
      expect(above.isPercentAlert, false);
      expect(above.isPriceAlert, true);

      const below = PriceAlertItem(
        symbol: 'BTC', alertType: 'below',
      );
      expect(below.isPercentAlert, false);
      expect(below.isPriceAlert, true);
    });

    test('typeEnum returns correct PriceAlertType', () {
      expect(
        const PriceAlertItem(symbol: 'BTC', alertType: 'above').typeEnum,
        PriceAlertType.above,
      );
      expect(
        const PriceAlertItem(symbol: 'BTC', alertType: 'below').typeEnum,
        PriceAlertType.below,
      );
      expect(
        const PriceAlertItem(symbol: 'BTC', alertType: 'percent_up').typeEnum,
        PriceAlertType.percentUp,
      );
    });

    test('toJson serializes correctly', () {
      const item = PriceAlertItem(
        id: 42,
        symbol: 'SOL',
        targetPrice: 200.0,
        alertType: 'above',
        targetPercent: null,
        referencePrice: 180.0,
        isActive: true,
        createdAt: '2026-03-01T12:00:00Z',
      );

      final json = item.toJson();

      expect(json['id'], 42);
      expect(json['symbol'], 'SOL');
      expect(json['target_price'], 200.0);
      expect(json['alert_type'], 'above');
      expect(json['is_active'], true);
    });
  });

  group('PriceAlertsResponse — Parsing', () {
    test('fromJson parses list of alerts', () {
      final json = {
        'success': true,
        'alerts': [
          {'id': 1, 'symbol': 'BTC', 'alert_type': 'above'},
          {'id': 2, 'symbol': 'ETH', 'alert_type': 'below', 'target_price': 3000.0},
        ],
      };

      final response = PriceAlertsResponse.fromJson(json);

      expect(response.success, true);
      expect(response.alerts.length, 2);
      expect(response.alerts[0].symbol, 'BTC');
      expect(response.alerts[1].symbol, 'ETH');
      expect(response.alerts[1].targetPrice, 3000.0);
    });

    test('fromJson handles empty alerts', () {
      final json = {'success': true, 'alerts': []};
      final response = PriceAlertsResponse.fromJson(json);
      expect(response.success, true);
      expect(response.alerts, isEmpty);
    });

    test('fromJson handles missing alerts field', () {
      final json = {'success': false};
      final response = PriceAlertsResponse.fromJson(json);
      expect(response.success, false);
      expect(response.alerts, isEmpty);
    });
  });

  group('PriceAlertRequest — Serialization', () {
    test('toJson includes all fields for above type', () {
      const request = PriceAlertRequest(
        anonymousId: 'anon_123',
        symbol: 'BTC',
        targetPrice: 75000.0,
        alertType: 'above',
      );

      final json = request.toJson();

      expect(json['DeviceID'], 'anon_123');
      expect(json['Symbol'], 'BTC');
      expect(json['TargetPrice'], 75000.0);
      expect(json['AlertType'], 'above');
      expect(json.containsKey('TargetPercent'), false);
    });

    test('toJson includes targetPercent for percent alerts', () {
      const request = PriceAlertRequest(
        anonymousId: 'anon_456',
        symbol: 'ETH',
        alertType: 'percent_up',
        targetPercent: 5.0,
      );

      final json = request.toJson();

      expect(json['DeviceID'], 'anon_456');
      expect(json['Symbol'], 'ETH');
      expect(json['AlertType'], 'percent_up');
      expect(json['TargetPercent'], 5.0);
      expect(json.containsKey('TargetPrice'), false);
    });
  });

  group('DeletePriceAlertRequest — Serialization', () {
    test('toJson includes alertId when provided', () {
      const request = DeletePriceAlertRequest(
        anonymousId: 'anon_123',
        alertId: 42,
      );

      final json = request.toJson();

      expect(json['DeviceID'], 'anon_123');
      expect(json['AlertID'], 42);
    });

    test('toJson includes symbol and alertType when alertId is null', () {
      const request = DeletePriceAlertRequest(
        anonymousId: 'anon_123',
        symbol: 'BTC',
        alertType: 'above',
      );

      final json = request.toJson();

      expect(json['DeviceID'], 'anon_123');
      expect(json['Symbol'], 'BTC');
      expect(json['AlertType'], 'above');
    });
  });

  group('BulkPricesResponse — Parsing', () {
    test('fromJson parses prices and uppercases symbols', () {
      final json = {
        'success': true,
        'prices': {
          'btc': 74500.50,
          'eth': 3200.0,
          'sol': 180.5,
        },
      };

      final response = BulkPricesResponse.fromJson(json);

      expect(response.success, true);
      expect(response.prices['BTC'], 74500.50);
      expect(response.prices['ETH'], 3200.0);
      expect(response.prices['SOL'], 180.5);
    });

    test('fromJson handles empty prices', () {
      final json = {'success': true, 'prices': {}};
      final response = BulkPricesResponse.fromJson(json);
      expect(response.success, true);
      expect(response.prices, isEmpty);
    });
  });

  group('NotificationApiResponse — Parsing', () {
    test('fromJson parses success response', () {
      final json = {'success': true, 'message': 'Alert created'};
      final response = NotificationApiResponse.fromJson(json);
      expect(response.success, true);
      expect(response.message, 'Alert created');
    });

    test('fromJson parses failure response', () {
      final json = {'success': false, 'message': 'Server error'};
      final response = NotificationApiResponse.fromJson(json);
      expect(response.success, false);
      expect(response.message, 'Server error');
    });
  });

  group('RegisterDeviceRequest — Serialization', () {
    test('toJson maps all fields correctly', () {
      const request = RegisterDeviceRequest(
        deviceToken: 'fcm_token_abc',
        deviceType: 'android',
        anonymousId: 'anon_1',
        deviceName: 'Pixel 7 Pro',
      );

      final json = request.toJson();

      expect(json['DeviceID'], 'anon_1');
      expect(json['DeviceToken'], 'fcm_token_abc');
      expect(json['DeviceType'], 'android');
      expect(json['DeviceName'], 'Pixel 7 Pro');
    });
  });
}
