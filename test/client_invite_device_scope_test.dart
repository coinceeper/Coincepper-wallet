import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/utils/referral_code_normalize.dart';

void main() {
  test('normalizeInviteInput extracts code for device-wide panel storage', () {
    expect(normalizeInviteInput('  ABC123  '), 'ABC123');
    expect(
      normalizeInviteInput('https://coinceeper.com/?invite_code=XYZ9'),
      'XYZ9',
    );
  });
}
