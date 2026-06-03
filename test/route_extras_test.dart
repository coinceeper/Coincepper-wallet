import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/navigation/route_extras.dart';
import 'package:my_flutter_app/navigation/route_paths.dart';

void main() {
  test('PasscodeRouteExtra accepts map legacy extras', () {
    final extra = PasscodeRouteExtra.from({
      'walletName': 'Main',
      'firstPasscode': '123456',
      'isFromBackground': true,
    });
    expect(extra?.walletName, 'Main');
    expect(extra?.firstPasscode, '123456');
    expect(extra?.isFromBackground, isTrue);
  });

  test('SendRouteExtra accepts typed instance', () {
    const typed = SendRouteExtra(qrArguments: {'foo': 'bar'});
    expect(SendRouteExtra.from(typed), same(typed));
  });

  test('RoutePaths.sendDetail builds path', () {
    expect(
      RoutePaths.sendDetail('abc'),
      '/send_detail/abc',
    );
  });
}
