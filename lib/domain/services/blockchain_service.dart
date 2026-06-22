import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/api_models.dart';
import '../../di/service_locator.dart';

/// Domain service for managing blockchain list from the API.
class BlockchainService {
  List<ApiBlockchain> _blockchains = [];
  VoidCallback? _onChange;

  /// [apiService] is accepted for backward compatibility with DI.
  /// The service uses [ServiceLocator] to resolve [ApiService].
  BlockchainService({ApiService? apiService});

  List<ApiBlockchain> get blockchains => _blockchains;

  void addListener(VoidCallback callback) {
    _onChange = callback;
  }

  void removeListener(VoidCallback callback) {
    _onChange = null;
  }

  Future<void> fetchBlockchains() async {
    try {
      final api = ServiceLocator.get<ApiService>();
      final response = await api.getBlockchains();
      _blockchains = response.blockchains;
      _notifyChange();
    } catch (e) {
      // Silently handle — blockchains list is non-critical for initial load
    }
  }

  void _notifyChange() {
    _onChange?.call();
  }
}
