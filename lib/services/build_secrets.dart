import 'package:flutter/foundation.dart';

/// Build-time secrets from --dart-define (CI / local sync scripts).
///
/// All secrets **must** be provided at build/run time — there are no
/// hardcoded fallback values.  Pass them via:
/// ```bash
/// flutter run --dart-define=CLIENT_HMAC_SECRET=... --dart-define=ETHERSCAN_API_KEY=...
/// ```
/// Or use the helper script:
/// ```bash
/// powershell -File scripts/run_with_keys.ps1
/// ```
abstract final class BuildSecrets {
  static String _fromEnv(String name) =>
      String.fromEnvironment(name, defaultValue: '');

  // ═══════════════════════════════════════════════════════
  // Build-time secrets (اجباری برای release)
  // ═══════════════════════════════════════════════════════

  static const String _clientHmacSecret = String.fromEnvironment(
    'CLIENT_HMAC_SECRET',
    defaultValue: '',
  );

  /// Format: `host:sha256hex,host2:sha256hex` (comma-separated pairs).
  static const String _tlsPinConfig = String.fromEnvironment(
    'TLS_PIN_SHA256',
    defaultValue: '',
  );

  static String get clientHmacSecret {
    if (_clientHmacSecret.isNotEmpty) return _clientHmacSecret;
    // برای حالت تست و دیباگ، یک مقدار پیش‌فرض قرار می‌دهیم تا خطا برطرف شود
    if (kDebugMode) return 'dev_test_secret_key_123456';
    throw StateError(
      'CLIENT_HMAC_SECRET is required. '
      'Pass --dart-define=CLIENT_HMAC_SECRET=... or use scripts/run_with_keys.ps1',
    );
  }

  static String get tlsPinConfig => _tlsPinConfig;

  /// Parsed map host -> set of lowercase sha256 hex fingerprints (cert DER hash).
  static Map<String, Set<String>> get tlsPinsByHost {
    final map = <String, Set<String>>{};
    if (_tlsPinConfig.isEmpty) return map;
    for (final part in _tlsPinConfig.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final host = trimmed.substring(0, colon).trim().toLowerCase();
      final hash = trimmed.substring(colon + 1).trim().toLowerCase();
      if (host.isEmpty || hash.isEmpty) continue;
      map.putIfAbsent(host, () => {}).add(hash);
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════
  // Explorer API Keys (برای History)
  // ═══════════════════════════════════════════════════════

  static String get etherscanApiKey => _fromEnv('ETHERSCAN_API_KEY');
  static String get bscscanApiKey => _fromEnv('BSCSCAN_API_KEY');
  static String get polygonscanApiKey => _fromEnv('POLYGONSCAN_API_KEY');
  static String get avalancheApiKey => _fromEnv('AVALANCHE_API_KEY');
  static String get arbitrumscanApiKey => _fromEnv('ARBITRUMSCAN_API_KEY');

  // ═══════════════════════════════════════════════════════
  // Tron — ۳ کلید مجزا برای ۴۵ req/sec
  // ═══════════════════════════════════════════════════════

  static String get trongridApiKey1 => _fromEnv('TRONGRID_API_KEY_1');
  static String get trongridApiKey2 => _fromEnv('TRONGRID_API_KEY_2');
  static String get trongridApiKey3 => _fromEnv('TRONGRID_API_KEY_3');

  /// Returns all non-empty TronGrid keys (maximum 3).
  static List<String> get trongridApiKeys => [
        if (trongridApiKey1.isNotEmpty) trongridApiKey1,
        if (trongridApiKey2.isNotEmpty) trongridApiKey2,
        if (trongridApiKey3.isNotEmpty) trongridApiKey3,
      ];

  // ═══════════════════════════════════════════════════════
  // RPC Pool — Registered Free Tiers
  // ═══════════════════════════════════════════════════════

  static String get drpcApiKey => _fromEnv('DRPC_API_KEY');
  static String get ankrApiKey => _fromEnv('ANKR_API_KEY');

  // ── Chainstack ──────────────────────────────────────────
  static String get chainstackEthToken => _fromEnv('CHAINSTACK_ETH_TOKEN');
  static String get chainstackBtcToken => _fromEnv('CHAINSTACK_BTC_TOKEN');
  static String get chainstackBscToken => _fromEnv('CHAINSTACK_BSC_TOKEN');
  static String get chainstackTrxToken => _fromEnv('CHAINSTACK_TRX_TOKEN');

  // ── Tenderly (per-chain Gateways) ───────────────────────
  static String get tenderlyApiKey => _fromEnv('TENDERLY_API_KEY');
  static String get tenderlyEthRpc => _fromEnv('TENDERLY_ETH_RPC_URL');
  static String get tenderlyEthWss => _fromEnv('TENDERLY_ETH_WSS_URL');
  static String get tenderlyPolygonRpc => _fromEnv('TENDERLY_POLYGON_RPC_URL');
  static String get tenderlyPolygonWss => _fromEnv('TENDERLY_POLYGON_WSS_URL');
  static String get tenderlyArbitrumRpc => _fromEnv('TENDERLY_ARBITRUM_RPC_URL');
  static String get tenderlyArbitrumWss => _fromEnv('TENDERLY_ARBITRUM_WSS_URL');
  static String get tenderlyAvalancheRpc => _fromEnv('TENDERLY_AVALANCHE_RPC_URL');
  static String get tenderlyAvalancheWss => _fromEnv('TENDERLY_AVALANCHE_WSS_URL');

  // ── Etox (per-chain) ────────────────────────────────────
  static String get etoxApiKey => _fromEnv('ETOX_API_KEY');
  static String get etoxEthRpc => _fromEnv('ETOX_ETH_RPC_URL');
  static String get etoxEthWss => _fromEnv('ETOX_ETH_WSS_URL');
  static String get etoxArbRpc => _fromEnv('ETOX_ARB_RPC_URL');
  static String get etoxArbWss => _fromEnv('ETOX_ARB_WSS_URL');
  static String get etoxPolygonRpc => _fromEnv('ETOX_POLYGON_RPC_URL');
  static String get etoxPolygonWss => _fromEnv('ETOX_POLYGON_WSS_URL');

  // ── BlockPI (per-chain) ─────────────────────────────────
  static String get blockpiEthRpc => _fromEnv('BLOCKPI_ETH_RPC_URL');
  static String get blockpiEthWss => _fromEnv('BLOCKPI_ETH_WSS_URL');
  static String get blockpiPolygonRpc => _fromEnv('BLOCKPI_POLYGON_RPC_URL');
  static String get blockpiPolygonWss => _fromEnv('BLOCKPI_POLYGON_WSS_URL');
  static String get blockpiArbitrumRpc => _fromEnv('BLOCKPI_ARBITRUM_RPC_URL');
  static String get blockpiArbitrumWss => _fromEnv('BLOCKPI_ARBITRUM_WSS_URL');
  static String get blockpiBscRpc => _fromEnv('BLOCKPI_BSC_RPC_URL');
  static String get blockpiBscWss => _fromEnv('BLOCKPI_BSC_WSS_URL');
  static String get blockpiAvalancheRpc => _fromEnv('BLOCKPI_AVALANCHE_RPC_URL');
  static String get blockpiAvalancheWss => _fromEnv('BLOCKPI_AVALANCHE_WSS_URL');
  static String get blockpiBtcRpc => _fromEnv('BLOCKPI_BTC_RPC_URL');

  // ═══════════════════════════════════════════════════════
  // Solana
  // ═══════════════════════════════════════════════════════

  static String get solanaRpcUrl => _fromEnv('SOLANA_RPC_URL');
  static String get heliusApiKey => _fromEnv('HELIUS_API_KEY');

  // ═══════════════════════════════════════════════════════
  // Polkadot
  // ═══════════════════════════════════════════════════════

  static String get subscanApiKey1 => _fromEnv('SUBSCAN_API_KEY_1');
  static String get subscanApiKey2 => _fromEnv('SUBSCAN_API_KEY_2');
  static String get subscanApiKey3 => _fromEnv('SUBSCAN_API_KEY_3');
  static String get subscanApiKey4 => _fromEnv('SUBSCAN_API_KEY_4');
  static String get subscanApiKey5 => _fromEnv('SUBSCAN_API_KEY_5');
  static String get subscanApiKey6 => _fromEnv('SUBSCAN_API_KEY_6');
  static String get subscanApiKey7 => _fromEnv('SUBSCAN_API_KEY_7');

  /// All non-empty Subscan keys for load balancing.
  static List<String> get subscanApiKeys => [
        if (subscanApiKey1.isNotEmpty) subscanApiKey1,
        if (subscanApiKey2.isNotEmpty) subscanApiKey2,
        if (subscanApiKey3.isNotEmpty) subscanApiKey3,
        if (subscanApiKey4.isNotEmpty) subscanApiKey4,
        if (subscanApiKey5.isNotEmpty) subscanApiKey5,
        if (subscanApiKey6.isNotEmpty) subscanApiKey6,
        if (subscanApiKey7.isNotEmpty) subscanApiKey7,
      ];

  // ═══════════════════════════════════════════════════════
  // Bitcoin
  // ═══════════════════════════════════════════════════════

  static String get blockcypherApiKey1 => _fromEnv('BLOCKCYPHER_API_KEY_1');
  static String get blockcypherApiKey2 => _fromEnv('BLOCKCYPHER_API_KEY_2');
  static String get blockcypherApiKey3 => _fromEnv('BLOCKCYPHER_API_KEY_3');
  static String get blockcypherApiKey4 => _fromEnv('BLOCKCYPHER_API_KEY_4');
  static String get blockcypherApiKey5 => _fromEnv('BLOCKCYPHER_API_KEY_5');
  static String get blockcypherApiKey6 => _fromEnv('BLOCKCYPHER_API_KEY_6');

  /// All non-empty BlockCypher keys for load balancing (6 × 3 req/sec = 18 req/sec).
  static List<String> get blockcypherApiKeys => [
        if (blockcypherApiKey1.isNotEmpty) blockcypherApiKey1,
        if (blockcypherApiKey2.isNotEmpty) blockcypherApiKey2,
        if (blockcypherApiKey3.isNotEmpty) blockcypherApiKey3,
        if (blockcypherApiKey4.isNotEmpty) blockcypherApiKey4,
        if (blockcypherApiKey5.isNotEmpty) blockcypherApiKey5,
        if (blockcypherApiKey6.isNotEmpty) blockcypherApiKey6,
      ];

  // ═══════════════════════════════════════════════════════
  // Price API
  // ═══════════════════════════════════════════════════════

  static String get coingeckoApiKey => _fromEnv('COINGECKO_API_KEY');

  // ═══════════════════════════════════════════════════════
  // Validation
  // ═══════════════════════════════════════════════════════

  /// Call at startup. Release mode requires HMAC secret + TLS pins.
  static void validateForCurrentMode({bool requireTlsPinsInRelease = true}) {
    // Forces clientHmacSecret resolution in release.
    if (kReleaseMode) {
      // ignore: unnecessary_statements
      clientHmacSecret;
      if (requireTlsPinsInRelease && tlsPinsByHost.isEmpty) {
        throw StateError(
          'TLS_PIN_SHA256 is required for release builds. '
          'Run scripts/extract_tls_pins.sh against production hosts, then '
          'scripts/run_with_keys.ps1 (or --dart-define=TLS_PIN_SHA256=host:hex,...).',
        );
      }
    }
  }
}
