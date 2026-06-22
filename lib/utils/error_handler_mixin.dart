import 'package:flutter/material.dart';
import '../services/error_service.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// A mixin that provides consistent error handling for all screens.
///
/// Instead of each screen managing its own local error modals, SnackBars,
/// or silent logging, they should use these helper methods which delegate
/// to the centralized [ErrorService].
///
/// Usage:
/// ```dart
/// class MyScreen extends StatefulWidget { ... }
/// class _MyScreenState extends State<MyScreen> with ErrorHandlerMixin { ... }
/// ```
///
/// All three methods log via [SecureLog] AND report to [ErrorService] so
/// the [GlobalErrorListener] shows a beautiful modal to the user.
mixin ErrorHandlerMixin<T extends StatefulWidget> on State<T> {
  /// Report an error through the centralized [ErrorService].
  ///
  /// Use this for any async operation failure (API calls, wallet operations,
  /// balance fetches, etc.) that the user should be aware of.
  ///
  /// [message] — a user-friendly fallback message when the error type
  /// cannot be automatically detected.
  ///
  /// [onRetry] — optional callback invoked when the user taps "Try Again"
  /// on the error modal.
  void reportError(
    Object error, {
    String? message,
    VoidCallback? onRetry,
    StackTrace? stackTrace,
  }) {
    try {
      ServiceLocator.get<ErrorService>().report(
        error,
        message: message,
        onRetry: onRetry,
        stackTrace: stackTrace,
      );
    } catch (e) {
      // Fallback: if ErrorService itself is not available, at least log.
      SecureLog.e('ErrorHandlerMixin: ErrorService unavailable', error: e);
    }
  }

  /// Report an error and execute [onError] callback (e.g. updating local state).
  ///
  /// Use this when the screen needs to update its own state in addition
  /// to showing the global error modal (e.g. resetting loading state).
  Future<void> reportErrorWithAction(
    Object error, {
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onError,
    StackTrace? stackTrace,
  }) async {
    onError?.call();
    reportError(error, message: message, onRetry: onRetry, stackTrace: stackTrace);
  }

  /// Wrap an async operation with automatic error reporting.
  ///
  /// Catches any exception thrown by [operation], reports it through
  /// [ErrorService], and optionally calls [onError] for local state cleanup.
  Future<R?> tryOrReport<R>(
    Future<R> Function() operation, {
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onError,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      reportErrorWithAction(
        e,
        message: message,
        onRetry: onRetry,
        onError: onError,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
