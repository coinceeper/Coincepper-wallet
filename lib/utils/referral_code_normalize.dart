/// Extracts a raw invite / referral code from pasted text or URLs for `/client/auth/register`.
///
/// Backend expects uppercase alphanumeric codes (matches ref codes / invite_links).
String normalizeInviteInput(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    try {
      final uri = Uri.parse(s);
      for (final key in [
        'code',
        'ref',
        'invite',
        'invite_code',
        'referral',
        'referral_code',
        'ref_code',
        'r',
        'promo',
        'invitation',
      ]) {
        final q = uri.queryParameters[key];
        if (q != null && q.trim().isNotEmpty) {
          s = q.trim();
          break;
        }
      }
      if (s == raw.trim()) {
        final seg = uri.pathSegments.where((e) => e.isNotEmpty).toList();
        if (seg.isNotEmpty) {
          final last = seg.last;
          if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(last) && last.length >= 4) {
            s = last;
          }
        }
      }
    } catch (_) {
      // fall through to strip chars below
    }
  }

  // Allow typical referral / invite codes (keep `_` for custom codes).
  final cleaned = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    if (RegExp(r'[A-Za-z0-9_]').hasMatch(c)) {
      cleaned.write(c);
    }
  }
  return cleaned.toString().toUpperCase();
}
