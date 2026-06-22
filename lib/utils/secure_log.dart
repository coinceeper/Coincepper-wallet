import 'package:flutter/foundation.dart';

/// Debug-only structured logging with automatic redaction of secrets.
///
/// All methods are no-ops in release mode. Sensitive patterns such as
/// seed phrases, mnemonics, private keys, and full response payloads
/// are redacted before being written to the console.
abstract final class SecureLog {
  // ─── Convenience level shorthands ─────────────────────────────

  /// Debug log — verbose information useful during development.
  static void d(String message, {Object? error, StackTrace? stackTrace}) {
    _log('🐛 DEBUG', message, error: error, stackTrace: stackTrace);
  }

  /// Info log — general flow information.
  static void i(String message, {Object? error, StackTrace? stackTrace}) {
    _log('💡 INFO', message, error: error, stackTrace: stackTrace);
  }

  /// Warning log — something unexpected but not an error.
  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    _log('⚠️ WARN', message, error: error, stackTrace: stackTrace);
  }

  /// Error log — something went wrong.
  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    _log('❌ ERROR', message, error: error, stackTrace: stackTrace);
  }

  // ─── Internal ─────────────────────────────────────────────────

  static void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) return;

    final safeMessage = _sanitize(message);
    debugPrint('$level $safeMessage');

    if (error != null) {
      final safeError = _sanitize('$error');
      debugPrint('$level   └─ Error: $safeError');
    }

    if (stackTrace != null) {
      debugPrint('$level   └─ StackTrace: $stackTrace');
    }
  }

  // ─── Sanitisation / redaction ─────────────────────────────────

  /// Scrubs known sensitive patterns from [input] and replaces them
  /// with a static `[redacted]` placeholder.
  static String _sanitize(String input) {
    var out = input;

    // 1. Full seed-phrase / mnemonic values printed inline.
    //    Catches patterns like "seed phrase: word1 word2 ... word12"
    out = out.replaceAllMapped(
      RegExp(
        r'((?:seed|mnemonic|recovery)\s*(?:phrase|words?|key)?'
        r'[^a-z]{1,3}\s*|mnemonic[=:]\s*)'
        r'([a-z]+\s+[a-z]+\s+[a-z]+\s*[a-z\s]{0,200})',
        caseSensitive: false,
      ),
      (_) => '${_.group(1)}[redacted]',
    );

    // 2. Standalone known-sensitive field names followed by any value.
    out = out.replaceAllMapped(
      RegExp(
        r'(passcode|private[_\s]?key|encrypted_private|salt'
        r'|master_seed|root_seed)'
        r'[^a-z]{1,3}.{0,120}',
        caseSensitive: false,
      ),
      (_) => '${_.group(1)}: [redacted]',
    );

    // 3. Leaked storage keys containing wallet/internal identifiers.
    out = out.replaceAllMapped(
      RegExp(
        r'(Mnemonic_|key:\s*Mnemonic_).{0,120}',
        caseSensitive: false,
      ),
      (_) => '${_.group(1)}[redacted]',
    );

    // 4. Full response objects / JSON blobs (catches both inline
    //    and pretty-printed payloads that may contain mnemonics).
    out = out.replaceAllMapped(
      RegExp(
        r'(Full Response|Response JSON|responseJson)[^a-z]{0,3}.{0,100}',
        caseSensitive: false,
      ),
      (_) => '${_.group(1)}: [redacted]',
    );

    // 5. Wallet debug dumps (list of maps with mnemonic or userId).
    out = out.replaceAllMapped(
      RegExp(
        r'Wallets after add\b.{0,500}',
        caseSensitive: false,
        dotAll: true,
      ),
      (_) => '[redacted wallet list]',
    );

    // 6. User / Wallet IDs (UUID-like or alphanumeric identifiers
    //    that follow common ID field names).
    //    Handles both exact "userId"/"userID" keywords AND contextual
    //    patterns like "for user:", "user:", "user =" where the keyword
    //    is the standalone word "user" (not combined with "Id").
    //    Also covers bare prepositional patterns like "for <UUID>" or
    //    "for: <UUID>" where the word "user" is omitted by the caller.
    out = out.replaceAllMapped(
      RegExp(
        r'(userID|userId|walletID|walletId|UserID|WalletID|'
        r'User[^a-z]{1,3}Id|for user[^a-z]{1,3}|for[:\s]{1,3}|'
        r'user[:\s=]{1,3}|of[:\s]{1,3}|User[:\s]{1,3})'
        r'(\S{8,80})',
        caseSensitive: false,
      ),
      (m) {
        final kw = m.group(1) ?? '';
        final val = m.group(2) ?? '';

        // Only redact if the captured value looks like an identifier
        // (UUID, hex, base64, or mixed alphanumeric of sufficient length)
        // and is NOT a common word, token symbol, or number.
        if (_looksLikeIdentifier(val)) {
          return kw.endsWith(' ') || kw.endsWith(':') || kw.endsWith('=')
              ? '$kw[redacted]'
              : '$kw: [redacted]';
        }
        return m.group(0) ?? out;
      },
    );

    // 7. Bare UUID / identifier patterns that follow common leak
    //    prefixes such as "for $uuid," "with $uuid " or embedded
    //    inside a log tag like "$userId/".
    out = out.replaceAllMapped(
      RegExp(
        r'(?:^|\s)(for\s+|with\s+|of\s+)([a-zA-Z0-9_-]{8,80})'
        r'(?:\s|$|,|/|\))',
        caseSensitive: false,
        multiLine: false,
      ),
      (m) {
        final prefix = m.group(1) ?? '';
        final candidate = m.group(2) ?? '';
        if (_looksLikeIdentifier(candidate)) {
          return '$prefix[redacted]';
        }
        return m.group(0) ?? out;
      },
    );

    // 8. Seed phrase length (leaks information about the phrase).
    out = out.replaceAllMapped(
      RegExp(
        r'(seed phrase|mnemonic)\s*(length|len)\b.{0,40}',
        caseSensitive: false,
      ),
      (_) => '[redacted phrase info]',
    );

    return out;
  }

  /// Returns true if [value] looks like a sensitive identifier (UUID,
  /// hex string, base64 token, or long alphanumeric) and is NOT a
  /// common word, crypto symbol, or plain number.
  static bool _looksLikeIdentifier(String value) {
    // Too short to be a meaningful identifier — let it through.
    if (value.length < 8) return false;

    // Pure numbers (e.g. "12345", "0.001") — not an identifier.
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) return false;

    // Common English words that might appear after "for", "of", "with".
    if (RegExp(r'^[a-zA-Z]{2,15}$').hasMatch(value)) {
      const commonWords = <String>{
        'the', 'this', 'that', 'these', 'those', 'user',
        'wallet', 'token', 'tokens', 'users', 'balance',
        'balances', 'true', 'false', 'null', 'none', 'all',
        'info', 'data', 'test', 'main', 'dev', 'prod',
      };
      if (commonWords.contains(value.toLowerCase())) return false;
    }

    // Everything that remains (UUIDs with hyphens, hex, base64, etc.)
    // is treated as a potential identifier and redacted.
    return true;
  }

  /// Explicitly redact a full object by converting it to a type-only
  /// representation. Use when you need to log *that* an object exists
  /// without exposing its contents.
  static String redact(Object object) {
    return '${object.runtimeType} [redacted]';
  }
}
