import 'package:flutter/foundation.dart';

/// Debug-only logging with redaction of secrets.
abstract final class SecureLog {
  static void d(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    
    final safeMessage = _sanitize(message);
    debugPrint(safeMessage);
    
    if (error != null) {
      debugPrint('  Error: $error');
    }
    
    if (stackTrace != null) {
      debugPrint('  StackTrace: $stackTrace');
    }
  }

  static String _sanitize(String input) {
    var out = input;
    out = out.replaceAllMapped(
      RegExp(r'(mnemonic|passcode|seed phrase|private[_\s]?key|salt|hash|secret|encrypted_private)[^\n]{0,120}', caseSensitive: false),
      (m) => '${m.group(1)}: [redacted]',
    );
    return out;
  }
}
