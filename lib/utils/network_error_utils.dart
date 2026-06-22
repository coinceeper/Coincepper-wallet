import 'dart:async';
import 'dart:io';

/// Shared utilities for determining transient network errors.
///
/// Extracted to eliminate duplication across providers (AppProvider and
/// TokenProvider previously each had their own copy of this logic).
class NetworkErrorUtils {
  NetworkErrorUtils._();

  /// Returns `true` if [error] represents a transient network failure that
  /// is worth retrying (connection errors, timeouts, 5xx server errors).
  static bool isTransientError(Exception error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is TimeoutException) return true;

    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception')) return true;
    if (errorStr.contains('connection')) return true;
    if (errorStr.contains('timeout')) return true;
    if (errorStr.contains('dioexception')) return true;
    if (errorStr.contains('network')) return true;
    if (errorStr.contains('500') ||
        errorStr.contains('502') ||
        errorStr.contains('503') ||
        errorStr.contains('504')) {
      return true;
    }

    return false;
  }
}
