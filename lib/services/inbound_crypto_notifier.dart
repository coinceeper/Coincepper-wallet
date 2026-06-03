import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import 'notification_helper.dart';

/// After history sync, notifies once per **new** completed inbound transfer.
class InboundCryptoNotifier {
  static String _prefsKey(String userId) {
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'inbound_crypto_notified_tx_v1_$safe';
  }

  static Future<void> processInboundFromHistory(
    String userId,
    List<Transaction> txs,
  ) async {
    if (userId.isEmpty || txs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(userId);
    final bootKey = '${key}_bootstrapped';
    final known = Set<String>.from(prefs.getStringList(key) ?? []);
    final bootstrapped = prefs.getBool(bootKey) ?? false;

    if (!bootstrapped) {
      for (final t in txs) {
        final dir = t.direction.toLowerCase();
        if (!dir.contains('in')) continue;
        if (t.txHash.isEmpty) continue;
        known.add(t.txHash);
      }
      await prefs.setStringList(key, known.toList());
      await prefs.setBool(bootKey, true);
      return;
    }

    for (final t in txs) {
      final dir = t.direction.toLowerCase();
      if (!dir.contains('in')) continue;
      final st = t.status.toLowerCase();
      if (st != 'completed' && st != 'success' && st != 'confirmed') continue;
      if (t.txHash.isEmpty) continue;
      if (known.contains(t.txHash)) continue;

      final amt = double.tryParse(t.amount) ?? 0;
      final sym = t.tokenSymbol.trim().isEmpty ? 'crypto' : t.tokenSymbol.trim();
      await NotificationHelper.showReceiveNotification(amt, sym);
      known.add(t.txHash);
    }

    var list = known.toList();
    if (list.length > 600) {
      list = list.sublist(list.length - 600);
    }
    await prefs.setStringList(key, list);
  }
}
