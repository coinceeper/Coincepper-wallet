/// Test FCM data payload parsing for price alerts.
///
/// This tests that when an FCM push arrives with `type: price_alert`,
/// all fields are correctly parsed into [FcmDataPayload] so the
/// router can display a proper local notification.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/models/notification_models.dart';

void main() {
  group('FcmDataPayload — Price Alert Parsing', () {
    test('parses price_alert type correctly', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
      });
      expect(payload.type, NotificationType.priceAlert);
    });

    test('parses all price alert fields from FCM data map', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'symbol': 'BTC',
        'price': '74500.50',
        'target_price': '75000',
        'alert_type': 'above',
        'title': 'BTC Hit Your Target!',
        'body': r'BTC is now $74,500 (target: $75,000)',
      });

      expect(payload.type, NotificationType.priceAlert);
      expect(payload.symbol, 'BTC');
      expect(payload.price, 74500.50);
      expect(payload.targetPrice, 75000);
      expect(payload.alertType, 'above');
      expect(payload.title, 'BTC Hit Your Target!');
      expect(payload.body, 'BTC is now \$74,500 (target: \$75,000)');
    });

    test('parses percent-based price alert fields', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'symbol': 'ETH',
        'price': '3200',
        'alert_type': 'percent_up',
        'target_percent': '5',
        'title': 'ETH Up 5%',
        'body': 'ETH increased by 5%',
      });

      expect(payload.type, NotificationType.priceAlert);
      expect(payload.symbol, 'ETH');
      expect(payload.price, 3200);
      // target_percent is not mapped — it's in raw
      expect(payload.raw['target_percent'], '5');
    });

    test('parses below-type price alert', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'symbol': 'SOL',
        'price': '120',
        'target_price': '125',
        'alert_type': 'below',
      });

      expect(payload.type, NotificationType.priceAlert);
      expect(payload.symbol, 'SOL');
      expect(payload.price, 120);
      expect(payload.targetPrice, 125);
      expect(payload.alertType, 'below');
    });

    test('fallback to unknown type for missing type field', () {
      final payload = FcmDataPayload.fromMap({});
      expect(payload.type, NotificationType.unknown);
    });

    test('handles null/empty symbol gracefully', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'symbol': '',
        'price': '50000',
      });
      expect(payload.symbol, '');
      expect(payload.price, 50000);
    });

    test('handles missing price gracefully (null)', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'symbol': 'BTC',
      });
      expect(payload.price, isNull);
    });

    test('preserves raw data map for additional fields', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'symbol': 'BTC',
        'extra_field': 'extra_value',
        'user_id': '12345',
      });

      expect(payload.raw['extra_field'], 'extra_value');
      expect(payload.raw['user_id'], '12345');
    });

    test('supports alternative field names (token, message, hash)', () {
      final payload = FcmDataPayload.fromMap({
        'type': 'price_alert',
        'token': 'BTC',
        'message': 'Bitcoin reached target',
        'hash': '0xabc123',
      });

      // symbol falls back to token
      expect(payload.symbol, 'BTC');
      // body falls back to message
      expect(payload.body, 'Bitcoin reached target');
      // txHash falls back to hash
      expect(payload.txHash, '0xabc123');
    });

    test('case-insensitive type matching via NotificationType.fromString', () {
      expect(
        NotificationType.fromString('PRICE_ALERT'),
        NotificationType.priceAlert,
      );
      expect(
        NotificationType.fromString('Price_Alert'),
        NotificationType.priceAlert,
      );
      expect(
        NotificationType.fromString('price_alert '),
        NotificationType.priceAlert,
      );
    });
  });

  group('NotificationType enum — priceAlert', () {
    test('value returns correct string', () {
      expect(NotificationType.priceAlert.value, 'price_alert');
    });

    test('channelId returns price_alerts channel', () {
      expect(NotificationType.priceAlert.channelId, 'price_alerts');
    });

    test('fromString handles price_alert correctly', () {
      expect(
        NotificationType.fromString('price_alert'),
        NotificationType.priceAlert,
      );
    });
  });

  group('PriceAlertType enum', () {
    test('apiValue returns correct backend string', () {
      expect(PriceAlertType.above.apiValue, 'above');
      expect(PriceAlertType.below.apiValue, 'below');
      expect(PriceAlertType.percentUp.apiValue, 'percent_up');
      expect(PriceAlertType.percentDown.apiValue, 'percent_down');
    });

    test('fromApi parses backend string correctly', () {
      expect(PriceAlertTypeX.fromApi('above'), PriceAlertType.above);
      expect(PriceAlertTypeX.fromApi('below'), PriceAlertType.below);
      expect(PriceAlertTypeX.fromApi('percent_up'), PriceAlertType.percentUp);
      expect(PriceAlertTypeX.fromApi('percent_down'), PriceAlertType.percentDown);
    });

    test('fromApi returns above for unknown values', () {
      expect(PriceAlertTypeX.fromApi('invalid'), PriceAlertType.above);
    });
  });
}
