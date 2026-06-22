import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/api_models.dart';
import '../../di/service_locator.dart';

/// Domain service for gas fee estimation.
///
/// Delegates to [ApiService.getGasFee] which returns a [GasFeeResponse]
/// with per-blockchain gas fee items.
class GasFeeService {
  Map<String, String> _gasFees = {};
  VoidCallback? _onChange;

  Map<String, String> get gasFees => _gasFees;

  void addListener(VoidCallback callback) {
    _onChange = callback;
  }

  void removeListener(VoidCallback callback) {
    _onChange = null;
  }

  Future<void> fetchGasFees() async {
    try {
      final api = ServiceLocator.get<ApiService>();
      final response = await api.getGasFee();
      _gasFees = _responseToMap(response);
      _notifyChange();
    } catch (e) {
      // Silently handle — gas fees are non-critical
    }
  }

  Future<String> ensureGasFee(String blockchainName) async {
    final key = blockchainName.toLowerCase();
    if (_gasFees.containsKey(key)) {
      return _gasFees[key]!;
    }
    await fetchGasFees();
    return _gasFees[key] ?? '';
  }

  Map<String, String> _responseToMap(GasFeeResponse response) {
    final map = <String, String>{};
    void addIfPresent(String key, GasFeeItem? item) {
      if (item != null && item.gasFee != null) {
        map[key] = item.gasFee!;
      }
    }
    addIfPresent('arbitrum', response.arbitrum);
    addIfPresent('avalanche', response.avalanche);
    addIfPresent('binance', response.binance);
    addIfPresent('bitcoin', response.bitcoin);
    addIfPresent('cardano', response.cardano);
    addIfPresent('cosmos', response.cosmos);
    addIfPresent('ethereum', response.ethereum);
    addIfPresent('fantom', response.fantom);
    addIfPresent('optimism', response.optimism);
    addIfPresent('polkadot', response.polkadot);
    addIfPresent('polygon', response.polygon);
    addIfPresent('solana', response.solana);
    addIfPresent('tron', response.tron);
    addIfPresent('xrp', response.xrp);
    return map;
  }

  void _notifyChange() {
    _onChange?.call();
  }
}
