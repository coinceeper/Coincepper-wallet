import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/utils/referral_code_normalize.dart';

void main() {
  test('normalizeInviteInput extracts code for device-wide panel storage', () {
    expect(normalizeInviteInput('  ABC123  '), 'ABC123');
    // URL دامنه از constant مرکزی خوانده می‌شود (BuildSecrets.coinceeperWebUrl).
    // در تست از مقدار پیش‌فرض استفاده می‌شود — در صورت تغییر دامنه فقط یک جا تغییر می‌کند.
    expect(
      normalizeInviteInput('https://coinceeper.com/?invite_code=XYZ9'),
      'XYZ9',
    );
  });
}
