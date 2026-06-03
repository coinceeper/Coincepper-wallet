import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../wallet/address_registry.dart';
import 'api_models.dart';
import 'notification_helper.dart';
import 'secure_storage.dart';
import 'service_provider.dart';

/// Poller Non-Custodial برای نوتیفیکیشن تراکنش‌های جدید
///
/// 🏛️ هماهنگ با معماری Active Address Registry سمت سرور:
/// ─────────────────────────────────────────────
/// ۱. هر ۶۰ ثانیه آدرس‌های Wallet را به V2 Cache Proxy می‌فرستد
/// ۲. سرور آدرس‌ها را در Active Address Registry ثبت می‌کند (TTL ۵ دقیقه)
/// ۳. Block Scanner سمت سرور فقط تراکنش‌های آدرس‌های فعال را اسکن می‌کند
/// ۴. تراکنش‌های جدید را در Hot Cache نگه می‌دارد و به کلاینت برمی‌گرداند
/// ۵. کلاینت تراکنش‌های جدید (نادیده) را شناسایی کرده و نوتیفیکیشن محلی نمایش می‌دهد
///
/// بدون UserID — کاملاً Non-Custodial
class V2NotificationPoller {
  V2NotificationPoller._();
  static final V2NotificationPoller instance = V2NotificationPoller._();

  Timer? _timer;

  /// مجموعه tx hashهایی که قبلاً دیده شده‌اند — persisted در SharedPreferences
  final Set<String> _seenTxHashes = {};
  static const String _seenKey = 'v2_notification_seen_hashes';

  /// آیا Poller در حال اجراست
  bool get isRunning => _timer != null;

  /// شروع Poller
  /// [walletId]: شناسه Wallet محلی (برای بازیابی آدرس‌ها از AddressRegistry)
  /// [interval]: فاصله چک کردن (پیش‌فرض ۶۰ ثانیه)
  Future<void> start({
    required String walletId,
    Duration interval = const Duration(seconds: 60),
  }) async {
    _timer?.cancel();

    // بارگذاری tx hashهای دیده شده قبلی
    await _loadSeenHashes();

    _timer = Timer.periodic(interval, (_) => _poll(walletId));

    // Poll اول فوری
    _poll(walletId);

    debugPrint('🔔 V2NotificationPoller started for walletId=$walletId');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('🔔 V2NotificationPoller stopped');
  }

  /// Reset — وقتی Wallet عوض می‌شود
  Future<void> reset() async {
    _seenTxHashes.clear();
    await _persistSeenHashes();
    debugPrint('🔔 V2NotificationPoller reset');
  }

  // ──── هسته اصلی Poller ────

  Future<void> _poll(String walletId) async {
    try {
      // ۱. آدرس‌های عمومی Wallet را از کش محلی بخوان
      final addresses = await AddressRegistry.instance.loadForWallet(walletId);
      if (addresses.isEmpty) return;

      final addrList = addresses.values.toList();

      // ۲. درخواست به V2 Cache Proxy
      //    سرور به صورت خودکار این آدرس‌ها را در Active Address Registry ثبت می‌کند
      final response = await ServiceProvider.instance.apiService.checkNotificationsV2(
        addresses: addrList,
      );

      if (response == null || !response.success) return;
      if (response.txs.isEmpty) return;

      // ۳. فیلتر تراکنش‌های جدید (که قبلاً ندیده‌ایم)
      final newTxs = <V2NotificationTx>[];
      for (final tx in response.txs) {
        if (!_seenTxHashes.contains(tx.hash)) {
          newTxs.add(tx);
          _seenTxHashes.add(tx.hash);
        }
      }

      if (newTxs.isEmpty) return;

      debugPrint('🔔 ${newTxs.length} new transaction(s) found');

      // ۴. ذخیره hashهای دیده شده
      await _trimAndPersist();

      // ۵. نمایش نوتیفیکیشن برای هر تراکنش جدید
      for (final tx in newTxs) {
        await _showNotificationForTx(tx);
      }
    } catch (e) {
      debugPrint('⚠️ V2NotificationPoller error: $e');
    }
  }

  /// کش زبان فعلی اپ
  String _currentLang = 'en';

  /// خواندن زبان ذخیره‌شده از SecureStorage
  Future<String> _getLanguageCode() async {
    try {
      final code = await SecureStorage.instance.getSecureData('current_language');
      if (code != null && code.isNotEmpty) return code;
    } catch (_) {}
    return 'en';
  }

  /// نمایش نوتیفیکیشن مناسب برای هر تراکنش
  Future<void> _showNotificationForTx(V2NotificationTx tx) async {
    final chain = tx.blockchain;
    _currentLang = await _getLanguageCode();

    // تعیین کانال بر اساس direction
    final String channelId;
    if (tx.direction == 'outbound') {
      channelId = 'send_channel';
    } else {
      channelId = 'receive_channel';
    }

    // تلاش برای پارس amount جهت نمایش
    String amountDisplay;
    if (tx.amount.isNotEmpty && tx.tokenSymbol.isNotEmpty) {
      final parsed = double.tryParse(tx.amount);
      if (parsed != null && parsed > 0) {
        amountDisplay = '${parsed.toStringAsFixed(6)} ${tx.tokenSymbol}';
      } else {
        amountDisplay = '${tx.amount} ${tx.tokenSymbol}';
      }
    } else {
      amountDisplay = '';
    }

    // عنوان و متن نوتیفیکیشن به زبان اپ
    final strings = _notifStrings(_currentLang);
    final String title;
    final String body;
    if (tx.direction == 'inbound') {
      title = '${strings.receivedEmoji} ${amountDisplay.isNotEmpty ? amountDisplay : strings.funds}';
      body = amountDisplay.isNotEmpty
          ? strings.receivedBody.replaceFirst('{amount}', amountDisplay).replaceFirst('{chain}', chain)
          : strings.newTxBody.replaceFirst('{chain}', chain);
    } else if (tx.direction == 'outbound') {
      title = '${strings.sentEmoji} ${amountDisplay.isNotEmpty ? amountDisplay : strings.funds}';
      body = amountDisplay.isNotEmpty
          ? strings.sentBody.replaceFirst('{amount}', amountDisplay).replaceFirst('{chain}', chain)
          : strings.newTxBody.replaceFirst('{chain}', chain);
    } else {
      // Fallback برای سرورهایی که direction ندارند (backward compatible)
      title = '${strings.newTxEmoji} ${strings.newTxTitle.replaceFirst('{chain}', chain)}';
      body = 'hash: ${tx.shortHash} | ${strings.addressLabel}: ${tx.shortAddress}';
    }

    await NotificationHelper.showNotification(
      channelId: channelId,
      title: title,
      body: body,
      payload: tx.hash,
    );
  }

  // ──── Localized notification strings ────

  static _NotifStrings _notifStrings(String lang) {
    switch (lang) {
      case 'fa':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'دریافت',
          receivedBody: 'شما {amount} در {chain} دریافت کردید',
          sentEmoji: '💸',
          sentTitle: 'ارسال',
          sentBody: 'شما {amount} در {chain} ارسال کردید',
          newTxEmoji: '💰',
          newTxTitle: 'تراکنش جدید در {chain}',
          newTxBody: 'تراکنش جدید در {chain}',
          funds: 'وجه',
          addressLabel: 'آدرس',
        );
      case 'ar':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'استلام',
          receivedBody: 'لقد استلمت {amount} في {chain}',
          sentEmoji: '💸',
          sentTitle: 'إرسال',
          sentBody: 'لقد أرسلت {amount} في {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'معاملة جديدة في {chain}',
          newTxBody: 'معاملة جديدة في {chain}',
          funds: 'أموال',
          addressLabel: 'العنوان',
        );
      case 'tr':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Alınan',
          receivedBody: '{chain} üzerinde {amount} aldınız',
          sentEmoji: '💸',
          sentTitle: 'Gönderilen',
          sentBody: '{chain} üzerinde {amount} gönderdiniz',
          newTxEmoji: '💰',
          newTxTitle: '{chain} üzerinde yeni işlem',
          newTxBody: '{chain} üzerinde yeni işlem',
          funds: 'tutar',
          addressLabel: 'Adres',
        );
      case 'ru':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Получено',
          receivedBody: 'Вы получили {amount} в {chain}',
          sentEmoji: '💸',
          sentTitle: 'Отправлено',
          sentBody: 'Вы отправили {amount} в {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'Новая транзакция в {chain}',
          newTxBody: 'Новая транзакция в {chain}',
          funds: 'средства',
          addressLabel: 'Адрес',
        );
      case 'zh':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: '收到',
          receivedBody: '您在 {chain} 收到了 {amount}',
          sentEmoji: '💸',
          sentTitle: '发送',
          sentBody: '您在 {chain} 发送了 {amount}',
          newTxEmoji: '💰',
          newTxTitle: '{chain} 新交易',
          newTxBody: '{chain} 新交易',
          funds: '资金',
          addressLabel: '地址',
        );
      case 'es':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Recibido',
          receivedBody: 'Recibiste {amount} en {chain}',
          sentEmoji: '💸',
          sentTitle: 'Enviado',
          sentBody: 'Enviaste {amount} en {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'Nueva transacción en {chain}',
          newTxBody: 'Nueva transacción en {chain}',
          funds: 'fondos',
          addressLabel: 'Dirección',
        );
      case 'fr':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Reçu',
          receivedBody: 'Vous avez reçu {amount} dans {chain}',
          sentEmoji: '💸',
          sentTitle: 'Envoyé',
          sentBody: 'Vous avez envoyé {amount} dans {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'Nouvelle transaction dans {chain}',
          newTxBody: 'Nouvelle transaction dans {chain}',
          funds: 'fonds',
          addressLabel: 'Adresse',
        );
      case 'de':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Erhalten',
          receivedBody: 'Sie haben {amount} in {chain} erhalten',
          sentEmoji: '💸',
          sentTitle: 'Gesendet',
          sentBody: 'Sie haben {amount} in {chain} gesendet',
          newTxEmoji: '💰',
          newTxTitle: 'Neue Transaktion in {chain}',
          newTxBody: 'Neue Transaktion in {chain}',
          funds: 'Betrag',
          addressLabel: 'Adresse',
        );
      case 'hi':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'प्राप्त',
          receivedBody: 'आपने {chain} में {amount} प्राप्त किया',
          sentEmoji: '💸',
          sentTitle: 'भेजा',
          sentBody: 'आपने {chain} में {amount} भेजा',
          newTxEmoji: '💰',
          newTxTitle: '{chain} में नया लेन-देन',
          newTxBody: '{chain} में नया लेन-देन',
          funds: 'राशि',
          addressLabel: 'पता',
        );
      case 'pt':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Recebido',
          receivedBody: 'Você recebeu {amount} em {chain}',
          sentEmoji: '💸',
          sentTitle: 'Enviado',
          sentBody: 'Você enviou {amount} em {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'Nova transação em {chain}',
          newTxBody: 'Nova transação em {chain}',
          funds: 'fundos',
          addressLabel: 'Endereço',
        );
      case 'id':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Diterima',
          receivedBody: 'Anda menerima {amount} di {chain}',
          sentEmoji: '💸',
          sentTitle: 'Dikirim',
          sentBody: 'Anda mengirim {amount} di {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'Transaksi baru di {chain}',
          newTxBody: 'Transaksi baru di {chain}',
          funds: 'dana',
          addressLabel: 'Alamat',
        );
      case 'ja':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: '受取',
          receivedBody: '{chain} で {amount} を受取りました',
          sentEmoji: '💸',
          sentTitle: '送金',
          sentBody: '{chain} で {amount} を送金しました',
          newTxEmoji: '💰',
          newTxTitle: '{chain} で新しいトランザクション',
          newTxBody: '{chain} で新しいトランザクション',
          funds: '資金',
          addressLabel: 'アドレス',
        );
      case 'ko':
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: '받음',
          receivedBody: '{chain}에서 {amount}을(를) 받았습니다',
          sentEmoji: '💸',
          sentTitle: '보냄',
          sentBody: '{chain}에서 {amount}을(를) 보냈습니다',
          newTxEmoji: '💰',
          newTxTitle: '{chain} 새 거래',
          newTxBody: '{chain} 새 거래',
          funds: '자금',
          addressLabel: '주소',
        );
      default:
        // English (fallback)
        return const _NotifStrings(
          receivedEmoji: '💰',
          receivedTitle: 'Received',
          receivedBody: 'You received {amount} in {chain}',
          sentEmoji: '💸',
          sentTitle: 'Sent',
          sentBody: 'You sent {amount} in {chain}',
          newTxEmoji: '💰',
          newTxTitle: 'New transaction in {chain}',
          newTxBody: 'New transaction in {chain}',
          funds: 'funds',
          addressLabel: 'address',
        );
    }
  }

  // ──── Persistence: tx hashهای دیده شده ────

  Future<void> _loadSeenHashes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        _seenTxHashes.addAll(decoded.cast<String>());
        debugPrint('🔔 Loaded ${_seenTxHashes.length} seen tx hashes');
      }
    } catch (_) {}
  }

  Future<void> _persistSeenHashes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenKey, jsonEncode(_seenTxHashes.toList()));
    } catch (_) {}
  }

  /// ذخیره و محدود کردن مجموعه hashها — حداکثر ۱۰۰۰ عدد
  Future<void> _trimAndPersist() async {
    if (_seenTxHashes.length > 1000) {
      // آخرین ۵۰۰ تا را نگه دار
      final trimmed = _seenTxHashes.take(500).toSet();
      _seenTxHashes.clear();
      _seenTxHashes.addAll(trimmed);
    }
    await _persistSeenHashes();
  }

  // ──── Health Check ────

  /// بررسی سلامت V2 Cache Proxy
  Future<V2HealthResponse?> checkHealth() async {
    return ServiceProvider.instance.apiService.checkHealthV2();
  }
}

/// Localized strings for transaction notifications.
class _NotifStrings {
  final String receivedEmoji;
  final String receivedTitle;
  final String receivedBody;
  final String sentEmoji;
  final String sentTitle;
  final String sentBody;
  final String newTxEmoji;
  final String newTxTitle;
  final String newTxBody;
  final String funds;
  final String addressLabel;

  const _NotifStrings({
    required this.receivedEmoji,
    required this.receivedTitle,
    required this.receivedBody,
    required this.sentEmoji,
    required this.sentTitle,
    required this.sentBody,
    required this.newTxEmoji,
    required this.newTxTitle,
    required this.newTxBody,
    required this.funds,
    required this.addressLabel,
  });
}
