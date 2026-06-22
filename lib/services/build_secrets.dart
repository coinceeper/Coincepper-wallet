import 'package:flutter/foundation.dart';
import '../utils/secure_log.dart';

/// Build-time secrets from --dart-define (CI / local sync scripts).
///
/// Pass them via:
/// ```bash
/// flutter run --dart-define=TLS_PIN_SHA256=...
/// ```
/// Or use the helper script:
/// ```bash
/// powershell -File scripts/run_with_keys.ps1
/// ```
abstract final class BuildSecrets {
  static String _fromEnv(String name) =>
      String.fromEnvironment(name, defaultValue: '');

  /// Format: `host:sha256hex,host2:sha256hex` (comma-separated pairs).
  static const String _tlsPinConfig = String.fromEnvironment(
    'TLS_PIN_SHA256',
    defaultValue: '',
  );

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
      // [CRASH-FIX] substring with length guards
      final host = colon <= trimmed.length
          ? trimmed.substring(0, colon).trim().toLowerCase()
          : '';
      final hash = (colon + 1) < trimmed.length
          ? trimmed.substring(colon + 1).trim().toLowerCase()
          : '';
      if (host.isEmpty || hash.isEmpty) continue;
      map.putIfAbsent(host, () => {}).add(hash);
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════
  // Explorer API Keys (برای History) — numbered for load balancing
  // ═══════════════════════════════════════════════════════

  // Etherscan (5 keys)
  static String get etherscanApiKey1 => _fromEnv('ETHERSCAN_API_KEY_1');
  static String get etherscanApiKey2 => _fromEnv('ETHERSCAN_API_KEY_2');
  static String get etherscanApiKey3 => _fromEnv('ETHERSCAN_API_KEY_3');
  static String get etherscanApiKey4 => _fromEnv('ETHERSCAN_API_KEY_4');
  static String get etherscanApiKey5 => _fromEnv('ETHERSCAN_API_KEY_5');

  /// Returns all non-empty Etherscan keys.
  static List<String> get etherscanApiKeys => [
        if (etherscanApiKey1.isNotEmpty) etherscanApiKey1,
        if (etherscanApiKey2.isNotEmpty) etherscanApiKey2,
        if (etherscanApiKey3.isNotEmpty) etherscanApiKey3,
        if (etherscanApiKey4.isNotEmpty) etherscanApiKey4,
        if (etherscanApiKey5.isNotEmpty) etherscanApiKey5,
      ];

  // BSCScan (4 keys)
  static String get bscscanApiKey1 => _fromEnv('BSCSCAN_API_KEY_1');
  static String get bscscanApiKey2 => _fromEnv('BSCSCAN_API_KEY_2');
  static String get bscscanApiKey3 => _fromEnv('BSCSCAN_API_KEY_3');
  static String get bscscanApiKey4 => _fromEnv('BSCSCAN_API_KEY_4');

  /// Returns all non-empty BSCScan keys.
  static List<String> get bscscanApiKeys => [
        if (bscscanApiKey1.isNotEmpty) bscscanApiKey1,
        if (bscscanApiKey2.isNotEmpty) bscscanApiKey2,
        if (bscscanApiKey3.isNotEmpty) bscscanApiKey3,
        if (bscscanApiKey4.isNotEmpty) bscscanApiKey4,
      ];

  // PolygonScan (3 keys)
  static String get polygonscanApiKey1 => _fromEnv('POLYGONSCAN_API_KEY_1');
  static String get polygonscanApiKey2 => _fromEnv('POLYGONSCAN_API_KEY_2');
  static String get polygonscanApiKey3 => _fromEnv('POLYGONSCAN_API_KEY_3');

  /// Returns all non-empty PolygonScan keys.
  static List<String> get polygonscanApiKeys => [
        if (polygonscanApiKey1.isNotEmpty) polygonscanApiKey1,
        if (polygonscanApiKey2.isNotEmpty) polygonscanApiKey2,
        if (polygonscanApiKey3.isNotEmpty) polygonscanApiKey3,
      ];

  // SnowTrace / Avalanche (3 keys)
  static String get avalancheApiKey1 => _fromEnv('AVALANCHE_API_KEY_1');
  static String get avalancheApiKey2 => _fromEnv('AVALANCHE_API_KEY_2');
  static String get avalancheApiKey3 => _fromEnv('AVALANCHE_API_KEY_3');

  /// Returns all non-empty Avalanche explorer keys.
  static List<String> get avalancheApiKeys => [
        if (avalancheApiKey1.isNotEmpty) avalancheApiKey1,
        if (avalancheApiKey2.isNotEmpty) avalancheApiKey2,
        if (avalancheApiKey3.isNotEmpty) avalancheApiKey3,
      ];

  // ArbitrumScan (3 keys)
  static String get arbitrumscanApiKey1 => _fromEnv('ARBITRUMSCAN_API_KEY_1');
  static String get arbitrumscanApiKey2 => _fromEnv('ARBITRUMSCAN_API_KEY_2');
  static String get arbitrumscanApiKey3 => _fromEnv('ARBITRUMSCAN_API_KEY_3');

  /// Returns all non-empty ArbitrumScan keys.
  static List<String> get arbitrumscanApiKeys => [
        if (arbitrumscanApiKey1.isNotEmpty) arbitrumscanApiKey1,
        if (arbitrumscanApiKey2.isNotEmpty) arbitrumscanApiKey2,
        if (arbitrumscanApiKey3.isNotEmpty) arbitrumscanApiKey3,
      ];

  /// Convenience: first non-empty explorer key for [blockchainName].
  /// Falls back to Etherscan keys if chain-specific key is unavailable.
  static String explorerApiKeyForBlockchain(String blockchainName) {
    final n = blockchainName.toLowerCase();
    List<String> keys;
    if (n.contains('bsc') || n.contains('binance')) {
      keys = bscscanApiKeys;
    } else if (n.contains('polygon')) {
      keys = polygonscanApiKeys;
    } else if (n.contains('avalanche')) {
      keys = avalancheApiKeys;
    } else if (n.contains('arbitrum')) {
      keys = arbitrumscanApiKeys;
    } else {
      keys = etherscanApiKeys;
    }
    if (keys.isNotEmpty) return keys.first;
    // Fallback to Etherscan
    final fallback = etherscanApiKeys;
    return fallback.isNotEmpty ? fallback.first : '';
  }

  // ═══════════════════════════════════════════════════════
  // Tron — ۱۲ کلید مجزا برای ۱۸۰ req/sec (هر کلید ۱۵ req/sec)
  // ═══════════════════════════════════════════════════════

  static String get trongridApiKey1 => _fromEnv('TRONGRID_API_KEY_1');
  static String get trongridApiKey2 => _fromEnv('TRONGRID_API_KEY_2');
  static String get trongridApiKey3 => _fromEnv('TRONGRID_API_KEY_3');
  static String get trongridApiKey4 => _fromEnv('TRONGRID_API_KEY_4');
  static String get trongridApiKey5 => _fromEnv('TRONGRID_API_KEY_5');
  static String get trongridApiKey6 => _fromEnv('TRONGRID_API_KEY_6');
  static String get trongridApiKey7 => _fromEnv('TRONGRID_API_KEY_7');
  static String get trongridApiKey8 => _fromEnv('TRONGRID_API_KEY_8');
  static String get trongridApiKey9 => _fromEnv('TRONGRID_API_KEY_9');
  static String get trongridApiKey10 => _fromEnv('TRONGRID_API_KEY_10');
  static String get trongridApiKey11 => _fromEnv('TRONGRID_API_KEY_11');
  static String get trongridApiKey12 => _fromEnv('TRONGRID_API_KEY_12');

  /// Returns all non-empty TronGrid keys (up to 12).
  static List<String> get trongridApiKeys => [
        if (trongridApiKey1.isNotEmpty) trongridApiKey1,
        if (trongridApiKey2.isNotEmpty) trongridApiKey2,
        if (trongridApiKey3.isNotEmpty) trongridApiKey3,
        if (trongridApiKey4.isNotEmpty) trongridApiKey4,
        if (trongridApiKey5.isNotEmpty) trongridApiKey5,
        if (trongridApiKey6.isNotEmpty) trongridApiKey6,
        if (trongridApiKey7.isNotEmpty) trongridApiKey7,
        if (trongridApiKey8.isNotEmpty) trongridApiKey8,
        if (trongridApiKey9.isNotEmpty) trongridApiKey9,
        if (trongridApiKey10.isNotEmpty) trongridApiKey10,
        if (trongridApiKey11.isNotEmpty) trongridApiKey11,
        if (trongridApiKey12.isNotEmpty) trongridApiKey12,
      ];

  // ═══════════════════════════════════════════════════════
  // RPC Pool — Registered Free Tiers (numbered for load balancing)
  // ═══════════════════════════════════════════════════════

  // ── dRPC (7 keys) ──────────────────────────────────────
  static String get drpcApiKey1 => _fromEnv('DRPC_API_KEY_1');
  static String get drpcApiKey2 => _fromEnv('DRPC_API_KEY_2');
  static String get drpcApiKey3 => _fromEnv('DRPC_API_KEY_3');
  static String get drpcApiKey4 => _fromEnv('DRPC_API_KEY_4');
  static String get drpcApiKey5 => _fromEnv('DRPC_API_KEY_5');
  static String get drpcApiKey6 => _fromEnv('DRPC_API_KEY_6');
  static String get drpcApiKey7 => _fromEnv('DRPC_API_KEY_7');

  /// Returns all non-empty dRPC keys (7 × 50M CU/mo).
  static List<String> get drpcApiKeys => [
        if (drpcApiKey1.isNotEmpty) drpcApiKey1,
        if (drpcApiKey2.isNotEmpty) drpcApiKey2,
        if (drpcApiKey3.isNotEmpty) drpcApiKey3,
        if (drpcApiKey4.isNotEmpty) drpcApiKey4,
        if (drpcApiKey5.isNotEmpty) drpcApiKey5,
        if (drpcApiKey6.isNotEmpty) drpcApiKey6,
        if (drpcApiKey7.isNotEmpty) drpcApiKey7,
      ];

  /// Convenience: first non-empty dRPC key (backward compat).
  static String get drpcApiKey =>
      drpcApiKeys.isNotEmpty ? drpcApiKeys.first : '';

  // ── Ankr (7 keys) ──────────────────────────────────────
  static String get ankrApiKey1 => _fromEnv('ANKR_API_KEY_1');
  static String get ankrApiKey2 => _fromEnv('ANKR_API_KEY_2');
  static String get ankrApiKey3 => _fromEnv('ANKR_API_KEY_3');
  static String get ankrApiKey4 => _fromEnv('ANKR_API_KEY_4');
  static String get ankrApiKey5 => _fromEnv('ANKR_API_KEY_5');
  static String get ankrApiKey6 => _fromEnv('ANKR_API_KEY_6');
  static String get ankrApiKey7 => _fromEnv('ANKR_API_KEY_7');

  /// Returns all non-empty Ankr keys (7 × 200M CU/mo).
  static List<String> get ankrApiKeys => [
        if (ankrApiKey1.isNotEmpty) ankrApiKey1,
        if (ankrApiKey2.isNotEmpty) ankrApiKey2,
        if (ankrApiKey3.isNotEmpty) ankrApiKey3,
        if (ankrApiKey4.isNotEmpty) ankrApiKey4,
        if (ankrApiKey5.isNotEmpty) ankrApiKey5,
        if (ankrApiKey6.isNotEmpty) ankrApiKey6,
        if (ankrApiKey7.isNotEmpty) ankrApiKey7,
      ];

  /// Convenience: first non-empty Ankr key (backward compat).
  static String get ankrApiKey =>
      ankrApiKeys.isNotEmpty ? ankrApiKeys.first : '';

  // ── Chainstack ──────────────────────────────────────────
  static String get chainstackEthToken => _fromEnv('CHAINSTACK_ETH_TOKEN');
  static String get chainstackBtcToken => _fromEnv('CHAINSTACK_BTC_TOKEN');
  static String get chainstackBscToken => _fromEnv('CHAINSTACK_BSC_TOKEN');
  static String get chainstackTrxToken => _fromEnv('CHAINSTACK_TRX_TOKEN');

  // ── Tenderly — ۳ حساب (هر کدام Gateway جدا) ────────────
  static String get tenderlyApiKey1 => _fromEnv('TENDERLY_API_KEY_1');
  static String get tenderlyApiKey2 => _fromEnv('TENDERLY_API_KEY_2');
  static String get tenderlyApiKey3 => _fromEnv('TENDERLY_API_KEY_3');

  static String get tenderlyEthRpc1 => _fromEnv('TENDERLY_ETH_RPC_URL_1');
  static String get tenderlyEthWss1 => _fromEnv('TENDERLY_ETH_WSS_URL_1');
  static String get tenderlyPolygonRpc1 => _fromEnv('TENDERLY_POLYGON_RPC_URL_1');
  static String get tenderlyPolygonWss1 => _fromEnv('TENDERLY_POLYGON_WSS_URL_1');
  static String get tenderlyArbitrumRpc1 => _fromEnv('TENDERLY_ARBITRUM_RPC_URL_1');
  static String get tenderlyArbitrumWss1 => _fromEnv('TENDERLY_ARBITRUM_WSS_URL_1');
  static String get tenderlyAvalancheRpc1 => _fromEnv('TENDERLY_AVALANCHE_RPC_URL_1');
  static String get tenderlyAvalancheWss1 => _fromEnv('TENDERLY_AVALANCHE_WSS_URL_1');

  static String get tenderlyEthRpc2 => _fromEnv('TENDERLY_ETH_RPC_URL_2');
  static String get tenderlyEthWss2 => _fromEnv('TENDERLY_ETH_WSS_URL_2');
  static String get tenderlyPolygonRpc2 => _fromEnv('TENDERLY_POLYGON_RPC_URL_2');
  static String get tenderlyPolygonWss2 => _fromEnv('TENDERLY_POLYGON_WSS_URL_2');
  static String get tenderlyArbitrumRpc2 => _fromEnv('TENDERLY_ARBITRUM_RPC_URL_2');
  static String get tenderlyArbitrumWss2 => _fromEnv('TENDERLY_ARBITRUM_WSS_URL_2');
  static String get tenderlyAvalancheRpc2 => _fromEnv('TENDERLY_AVALANCHE_RPC_URL_2');
  static String get tenderlyAvalancheWss2 => _fromEnv('TENDERLY_AVALANCHE_WSS_URL_2');

  static String get tenderlyEthRpc3 => _fromEnv('TENDERLY_ETH_RPC_URL_3');
  static String get tenderlyEthWss3 => _fromEnv('TENDERLY_ETH_WSS_URL_3');
  static String get tenderlyPolygonRpc3 => _fromEnv('TENDERLY_POLYGON_RPC_URL_3');
  static String get tenderlyPolygonWss3 => _fromEnv('TENDERLY_POLYGON_WSS_URL_3');
  static String get tenderlyArbitrumRpc3 => _fromEnv('TENDERLY_ARBITRUM_RPC_URL_3');
  static String get tenderlyArbitrumWss3 => _fromEnv('TENDERLY_ARBITRUM_WSS_URL_3');
  static String get tenderlyAvalancheRpc3 => _fromEnv('TENDERLY_AVALANCHE_RPC_URL_3');
  static String get tenderlyAvalancheWss3 => _fromEnv('TENDERLY_AVALANCHE_WSS_URL_3');

  /// Convenience: first non-empty Tenderly account URLs (backward compat).
  static String get tenderlyApiKey => tenderlyApiKey1;
  static String get tenderlyEthRpc => tenderlyEthRpc1;
  static String get tenderlyEthWss => tenderlyEthWss1;
  static String get tenderlyPolygonRpc => tenderlyPolygonRpc1;
  static String get tenderlyPolygonWss => tenderlyPolygonWss1;
  static String get tenderlyArbitrumRpc => tenderlyArbitrumRpc1;
  static String get tenderlyArbitrumWss => tenderlyArbitrumWss1;
  static String get tenderlyAvalancheRpc => tenderlyAvalancheRpc1;
  static String get tenderlyAvalancheWss => tenderlyAvalancheWss1;

  // ── Etox (6 keys, per-chain URLs numbered) ─────────────
  static String get etoxApiKey1 => _fromEnv('ETOX_API_KEY_1');
  static String get etoxApiKey2 => _fromEnv('ETOX_API_KEY_2');
  static String get etoxApiKey3 => _fromEnv('ETOX_API_KEY_3');
  static String get etoxApiKey4 => _fromEnv('ETOX_API_KEY_4');
  static String get etoxApiKey5 => _fromEnv('ETOX_API_KEY_5');
  static String get etoxApiKey6 => _fromEnv('ETOX_API_KEY_6');

  /// All non-empty Etox API keys.
  static List<String> get etoxApiKeys => [
        if (etoxApiKey1.isNotEmpty) etoxApiKey1,
        if (etoxApiKey2.isNotEmpty) etoxApiKey2,
        if (etoxApiKey3.isNotEmpty) etoxApiKey3,
        if (etoxApiKey4.isNotEmpty) etoxApiKey4,
        if (etoxApiKey5.isNotEmpty) etoxApiKey5,
        if (etoxApiKey6.isNotEmpty) etoxApiKey6,
      ];

  /// Convenience: first non-empty Etox key (backward compat).
  static String get etoxApiKey =>
      etoxApiKeys.isNotEmpty ? etoxApiKeys.first : '';

  static String get etoxEthRpc1 => _fromEnv('ETOX_ETH_RPC_URL_1');
  static String get etoxEthWss1 => _fromEnv('ETOX_ETH_WSS_URL_1');
  static String get etoxArbRpc1 => _fromEnv('ETOX_ARB_RPC_URL_1');
  static String get etoxArbWss1 => _fromEnv('ETOX_ARB_WSS_URL_1');
  static String get etoxPolygonRpc1 => _fromEnv('ETOX_POLYGON_RPC_URL_1');
  static String get etoxPolygonWss1 => _fromEnv('ETOX_POLYGON_WSS_URL_1');

  static String get etoxEthRpc2 => _fromEnv('ETOX_ETH_RPC_URL_2');
  static String get etoxEthWss2 => _fromEnv('ETOX_ETH_WSS_URL_2');
  static String get etoxArbRpc2 => _fromEnv('ETOX_ARB_RPC_URL_2');
  static String get etoxArbWss2 => _fromEnv('ETOX_ARB_WSS_URL_2');
  static String get etoxPolygonRpc2 => _fromEnv('ETOX_POLYGON_RPC_URL_2');
  static String get etoxPolygonWss2 => _fromEnv('ETOX_POLYGON_WSS_URL_2');

  static String get etoxEthRpc3 => _fromEnv('ETOX_ETH_RPC_URL_3');
  static String get etoxEthWss3 => _fromEnv('ETOX_ETH_WSS_URL_3');
  static String get etoxArbRpc3 => _fromEnv('ETOX_ARB_RPC_URL_3');
  static String get etoxArbWss3 => _fromEnv('ETOX_ARB_WSS_URL_3');
  static String get etoxPolygonRpc3 => _fromEnv('ETOX_POLYGON_RPC_URL_3');
  static String get etoxPolygonWss3 => _fromEnv('ETOX_POLYGON_WSS_URL_3');

  static String get etoxEthRpc4 => _fromEnv('ETOX_ETH_RPC_URL_4');
  static String get etoxEthWss4 => _fromEnv('ETOX_ETH_WSS_URL_4');
  static String get etoxArbRpc4 => _fromEnv('ETOX_ARB_RPC_URL_4');
  static String get etoxArbWss4 => _fromEnv('ETOX_ARB_WSS_URL_4');
  static String get etoxPolygonRpc4 => _fromEnv('ETOX_POLYGON_RPC_URL_4');
  static String get etoxPolygonWss4 => _fromEnv('ETOX_POLYGON_WSS_URL_4');

  static String get etoxEthRpc5 => _fromEnv('ETOX_ETH_RPC_URL_5');
  static String get etoxEthWss5 => _fromEnv('ETOX_ETH_WSS_URL_5');
  static String get etoxArbRpc5 => _fromEnv('ETOX_ARB_RPC_URL_5');
  static String get etoxArbWss5 => _fromEnv('ETOX_ARB_WSS_URL_5');
  static String get etoxPolygonRpc5 => _fromEnv('ETOX_POLYGON_RPC_URL_5');
  static String get etoxPolygonWss5 => _fromEnv('ETOX_POLYGON_WSS_URL_5');

  static String get etoxEthRpc6 => _fromEnv('ETOX_ETH_RPC_URL_6');
  static String get etoxEthWss6 => _fromEnv('ETOX_ETH_WSS_URL_6');
  static String get etoxArbRpc6 => _fromEnv('ETOX_ARB_RPC_URL_6');
  static String get etoxArbWss6 => _fromEnv('ETOX_ARB_WSS_URL_6');
  static String get etoxPolygonRpc6 => _fromEnv('ETOX_POLYGON_RPC_URL_6');
  static String get etoxPolygonWss6 => _fromEnv('ETOX_POLYGON_WSS_URL_6');

  /// Convenience: first non-empty Etox per-chain URLs (backward compat).
  static String get etoxEthRpc => etoxEthRpc1;
  static String get etoxEthWss => etoxEthWss1;
  static String get etoxArbRpc => etoxArbRpc1;
  static String get etoxArbWss => etoxArbWss1;
  static String get etoxPolygonRpc => etoxPolygonRpc1;
  static String get etoxPolygonWss => etoxPolygonWss1;

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
  // Solana — ۳ RPC endpoint + ۹ Helius key
  // ═══════════════════════════════════════════════════════

  static String get solanaRpcUrl1 => _fromEnv('SOLANA_RPC_URL_1');
  static String get solanaRpcUrl2 => _fromEnv('SOLANA_RPC_URL_2');
  static String get solanaRpcUrl3 => _fromEnv('SOLANA_RPC_URL_3');

  /// All non-empty Solana RPC URLs.
  static List<String> get solanaRpcUrls => [
        if (solanaRpcUrl1.isNotEmpty) solanaRpcUrl1,
        if (solanaRpcUrl2.isNotEmpty) solanaRpcUrl2,
        if (solanaRpcUrl3.isNotEmpty) solanaRpcUrl3,
      ];

  /// Convenience: first non-empty Solana RPC URL (backward compat).
  static String get solanaRpcUrl =>
      solanaRpcUrls.isNotEmpty ? solanaRpcUrls.first : '';

  static String get solanaWsUrl1 => _fromEnv('SOLANA_WS_URL_1');
  static String get solanaWsUrl2 => _fromEnv('SOLANA_WS_URL_2');
  static String get solanaWsUrl3 => _fromEnv('SOLANA_WS_URL_3');

  /// All non-empty Solana WS URLs.
  static List<String> get solanaWsUrls => [
        if (solanaWsUrl1.isNotEmpty) solanaWsUrl1,
        if (solanaWsUrl2.isNotEmpty) solanaWsUrl2,
        if (solanaWsUrl3.isNotEmpty) solanaWsUrl3,
      ];

  // ── Helius (9 keys) ─────────────────────────────────────
  static String get heliusApiKey1 => _fromEnv('HELIUS_API_KEY_1');
  static String get heliusApiKey2 => _fromEnv('HELIUS_API_KEY_2');
  static String get heliusApiKey3 => _fromEnv('HELIUS_API_KEY_3');
  static String get heliusApiKey4 => _fromEnv('HELIUS_API_KEY_4');
  static String get heliusApiKey5 => _fromEnv('HELIUS_API_KEY_5');
  static String get heliusApiKey6 => _fromEnv('HELIUS_API_KEY_6');
  static String get heliusApiKey7 => _fromEnv('HELIUS_API_KEY_7');
  static String get heliusApiKey8 => _fromEnv('HELIUS_API_KEY_8');
  static String get heliusApiKey9 => _fromEnv('HELIUS_API_KEY_9');

  /// All non-empty Helius API keys.
  static List<String> get heliusApiKeys => [
        if (heliusApiKey1.isNotEmpty) heliusApiKey1,
        if (heliusApiKey2.isNotEmpty) heliusApiKey2,
        if (heliusApiKey3.isNotEmpty) heliusApiKey3,
        if (heliusApiKey4.isNotEmpty) heliusApiKey4,
        if (heliusApiKey5.isNotEmpty) heliusApiKey5,
        if (heliusApiKey6.isNotEmpty) heliusApiKey6,
        if (heliusApiKey7.isNotEmpty) heliusApiKey7,
        if (heliusApiKey8.isNotEmpty) heliusApiKey8,
        if (heliusApiKey9.isNotEmpty) heliusApiKey9,
      ];

  /// Convenience: first non-empty Helius key (backward compat).
  static String get heliusApiKey =>
      heliusApiKeys.isNotEmpty ? heliusApiKeys.first : '';

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
  // Python Backend Proxy — مسیر اصلی تمام درخواست‌ها
  // ═══════════════════════════════════════════════════════

  /// Base URL بک‌اند پراکسی پایتون.
  /// در حالت Fallback (بک‌اند در دسترس نباشد)، اپ مستقیم به APIهای خارجی وصل می‌شود.
  static String get proxyBaseUrl => _fromEnv('PROXY_BASE_URL');

  /// آیا بک‌اند پراکسی فعال است؟ (با چک کردن PROXY_BASE_URL)
  static bool get isProxyConfigured => proxyBaseUrl.isNotEmpty;

  // ═══════════════════════════════════════════════════════
  // Price API — ۶ کلید CoinGecko برای ۳۰۰ calls/min
  // ═══════════════════════════════════════════════════════

  static String get coingeckoApiKey1 => _fromEnv('COINGECKO_API_KEY_1');
  static String get coingeckoApiKey2 => _fromEnv('COINGECKO_API_KEY_2');
  static String get coingeckoApiKey3 => _fromEnv('COINGECKO_API_KEY_3');
  static String get coingeckoApiKey4 => _fromEnv('COINGECKO_API_KEY_4');
  static String get coingeckoApiKey5 => _fromEnv('COINGECKO_API_KEY_5');
  static String get coingeckoApiKey6 => _fromEnv('COINGECKO_API_KEY_6');

  /// Returns all non-empty CoinGecko Pro keys for round-robin.
  static List<String> get coingeckoApiKeys => [
        if (coingeckoApiKey1.isNotEmpty) coingeckoApiKey1,
        if (coingeckoApiKey2.isNotEmpty) coingeckoApiKey2,
        if (coingeckoApiKey3.isNotEmpty) coingeckoApiKey3,
        if (coingeckoApiKey4.isNotEmpty) coingeckoApiKey4,
        if (coingeckoApiKey5.isNotEmpty) coingeckoApiKey5,
        if (coingeckoApiKey6.isNotEmpty) coingeckoApiKey6,
      ];

  // ═══════════════════════════════════════════════════════
  // TSP Agent Ops Secrets (از --dart-define)
  // ═══════════════════════════════════════════════════════

  /// Base URL برای TSP Agent Ops endpoint.
  /// مثال: https://your-host.com/api/v1/agent-ingest/ops
  static const String tspOpsBaseUrl = String.fromEnvironment(
    'TSP_OPS_BASE_URL',
    defaultValue: '',
  );

  /// Secret مخصوص ingest برای TSP Agent.
  static const String tspOpsIngestSecret = String.fromEnvironment(
    'TSP_OPS_INGEST_SECRET',
    defaultValue: '',
  );

  /// آیا هر دو متغیر TSP_OPS تنظیم شده‌اند؟
  static bool get isTspOpsConfigured =>
      tspOpsBaseUrl.isNotEmpty && tspOpsIngestSecret.isNotEmpty;

  // ═══════════════════════════════════════════════════════
  // Client Panel Base URL (از --dart-define)
  // ═══════════════════════════════════════════════════════

  /// Base URL پنل کاربری بک‌اند (Client Panel).
  /// مثال: https://your-host.com/api/v1/client
  static const String clientPanelBaseUrl = String.fromEnvironment(
    'CLIENT_PANEL_BASE_URL',
    defaultValue: '',
  );

  // ═══════════════════════════════════════════════════════════════
  // GEO Proxy Configuration — توزیع جغرافیایی ترافیک
  // ═══════════════════════════════════════════════════════════════

  /// JSON پیکربندی GEO Proxy Pool.
  ///
  /// فرمت:
  /// ```json
  /// {
  ///   "proxies": [
  ///     {"id":"us-1","region":"US","host":"1.2.3.4","port":3128,"protocol":"http"},
  ///     {"id":"gb-1","region":"GB","host":"5.6.7.8","port":3128,"protocol":"http","username":"u","password":"p"}
  ///   ]
  /// }
  /// ```
  static const String geoProxyConfig = String.fromEnvironment(
    'GEO_PROXY_CONFIG',
    defaultValue: '',
  );

  /// آیا GEO Proxy Pool از طریق BuildSecrets پیکربندی شده؟
  static bool get isGeoProxyConfigured => geoProxyConfig.isNotEmpty;

  // ═══════════════════════════════════════════════════════
  // CoinCeeper API Base URLs (از --dart-define)
  // ═══════════════════════════════════════════════════════

  /// CoinCeeper API V1 — باید از طریق --dart-define=COINCEEPER_API_BASE_URL=... تنظیم شود.
  /// 🚨 در Release Build این متغیر اجباری است.
  static String get coinceeperApiBaseUrl => _fromEnv('COINCEEPER_API_BASE_URL');

  /// CoinCeeper API V2 (Cache Proxy) — باید از طریق --dart-define تنظیم شود.
  /// 🚨 در Release Build این متغیر اجباری است.
  static String get coinceeperApiBaseUrlV2 => _fromEnv('COINCEEPER_API_BASE_URL_V2');

  /// URL وب‌سایت CoinCeeper — باید از طریق --dart-define تنظیم شود.
  /// 🚨 در Release Build این متغیر اجباری است.
  static String get coinceeperWebUrl => _fromEnv('COINCEEPER_WEB_URL');

  /// URL نسخه‌یابی اپ — باید از طریق --dart-define تنظیم شود.
  /// 🚨 در Release Build این متغیر اجباری است.
  static String get coinceeperVersionApiUrl => _fromEnv('COINCEEPER_VERSION_API_URL');

  // ═══════════════════════════════════════════════════════
  // Validation
  // ═══════════════════════════════════════════════════════

  /// Call at startup. Release mode requires TLS pins + API URLs.
  static void validateForCurrentMode({
    bool requireTlsPinsInRelease = true,
    bool requireTspOpsInRelease = false,
    bool requireApiUrlsInRelease = true,
  }) {
    // در Debug Mode هشدار می‌دهد، در Release Mode خطا می‌دهد
    if (kReleaseMode) {
      if (requireTlsPinsInRelease && tlsPinsByHost.isEmpty) {
        throw StateError(
          'TLS_PIN_SHA256 is required for release builds. '
          'Run scripts/extract_tls_pins.sh against production hosts, then '
          'scripts/run_with_keys.ps1 (or --dart-define=TLS_PIN_SHA256=host:hex,...).',
        );
      }
      if (requireTspOpsInRelease && !isTspOpsConfigured) {
        throw StateError(
          'TSP_OPS_BASE_URL and TSP_OPS_INGEST_SECRET are required for release builds. '
          'Pass them via --dart-define (see scripts/run_with_keys.ps1 or .env.example).',
        );
      }
      if (requireApiUrlsInRelease) {
        _requireUrl('COINCEEPER_API_BASE_URL', coinceeperApiBaseUrl);
        _requireUrl('COINCEEPER_API_BASE_URL_V2', coinceeperApiBaseUrlV2);
        _requireUrl('COINCEEPER_WEB_URL', coinceeperWebUrl);
        _requireUrl('COINCEEPER_VERSION_API_URL', coinceeperVersionApiUrl);
      }
    } else {
      // در Debug Mode فقط هشدار می‌دهد
      _warnIfEmpty('COINCEEPER_API_BASE_URL', coinceeperApiBaseUrl);
      _warnIfEmpty('COINCEEPER_API_BASE_URL_V2', coinceeperApiBaseUrlV2);
      _warnIfEmpty('COINCEEPER_WEB_URL', coinceeperWebUrl);
      _warnIfEmpty('COINCEEPER_VERSION_API_URL', coinceeperVersionApiUrl);
    }
  }

  static void _requireUrl(String name, String value) {
    if (value.isEmpty) {
      throw StateError(
        '$name is required for release builds. Pass it via --dart-define=$name=...',
      );
    }
  }

  static void _warnIfEmpty(String name, String value) {
    if (value.isEmpty && !kReleaseMode) {
      // ignore: avoid_print
      SecureLog.w('Build secret $name is empty');
    }
  }
}
