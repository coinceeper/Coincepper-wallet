import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
import '../domain/interfaces/i_error_service.dart';
import '../models/app_error.dart';
import '../utils/secure_log.dart';

/// Centralized error reporting and user-notification service.
///
/// ## Philosophy
///
/// Every layer of the app (providers, services, screens) should catch
/// errors and forward them **here** instead of calling `print()`.
/// [ErrorService] will:
///   1. Log the error via [SecureLog] with full context.
///   2. Expose the error on a [Stream] so that any UI listener (e.g.
///      a global overlay or a screen) can display it to the user.
///
/// ## Architecture
///
/// ```
/// Provider / Service                    ErrorService
/// ┌──────────────────┐     .report()   ┌──────────────────────┐
/// │ catch (e) {      │ ──────────────> │ 1. SecureLog.e()    │
/// │   ErrorService   │                │ 2. _errorController │
/// │     .report(e)   │                │    .add(appError)    │
/// │ }                │                └─────────┬────────────┘
/// └──────────────────┘                           │
///                                                 │ Stream<AppError>
/// GlobalErrorListener / Screen                    ▼
/// ┌─────────────────────────────────────────────────────────────┐
/// │ errorService.errorStream.listen((error) => show(error))     │
/// └─────────────────────────────────────────────────────────────┘
/// ```
class ErrorService implements IErrorService {
  ErrorService();

  ErrorService._internal();

  static ErrorService get instance => ServiceLocator.get<ErrorService>();

  // ─── Stream infrastructure ─────────────────────────────────
  final StreamController<AppError> _errorController =
      StreamController<AppError>.broadcast();

  /// Stream that any UI listener can subscribe to in order to
  /// receive user-facing errors in real time.
  Stream<AppError> get errorStream => _errorController.stream;

  /// The most recent error (useful for providers that want to
  /// expose the last error to their consumers).
  AppError? _lastError;
  AppError? get lastError => _lastError;

  /// A queue of unreported errors.  Useful when the user is
  /// already looking at one error and new ones arrive — we buffer
  /// them and show them one by one.
  final Queue<AppError> _pendingErrors = Queue<AppError>();

  /// Whether an error is currently being displayed (used by UI
  /// layer to prevent stacking).
  bool _isDisplayingError = false;
  bool get isDisplayingError => _isDisplayingError;

  // ─── Public API ────────────────────────────────────────────

  /// Report an error.  Always logs via [SecureLog]; if [showToUser]
  /// is true (default), the error is also published on the stream
  /// for the UI layer to display.
  @override
  void report(
    Object error, {
    String? message,
    VoidCallback? onRetry,
    bool showToUser = true,
    StackTrace? stackTrace,
  }) {
    // Build structured AppError
    final appError = AppError.fromException(
      error,
      onRetry: onRetry,
      fallbackMessage: message,
    );

    // Always log
    SecureLog.e(
      message ?? 'Error: ${error.runtimeType}',
      error: error,
      stackTrace: stackTrace,
    );

    _lastError = appError;

    if (!showToUser) return;

    if (_isDisplayingError) {
      // Queue for later display
      _pendingErrors.add(appError);
    } else {
      _emit(appError);
    }
  }

  /// Report a custom [AppError] directly (bypasses type detection).
  void reportAppError(AppError appError, {StackTrace? stackTrace}) {
    SecureLog.e(
      appError.message,
      error: appError,
      stackTrace: stackTrace,
    );

    _lastError = appError;

    if (_isDisplayingError) {
      _pendingErrors.add(appError);
    } else {
      _emit(appError);
    }
  }

  /// Clear the last error (call this after the user has seen it).
  void clearLastError() {
    _lastError = null;
  }

  /// Mark that the current error display has been dismissed, and
  /// show the next pending error if any.
  void onErrorDismissed() {
    _isDisplayingError = false;
    _lastError = null;

    if (_pendingErrors.isNotEmpty) {
      final next = _pendingErrors.removeFirst();
      _emit(next);
    }
  }

  // ─── Internal ──────────────────────────────────────────────

  void _emit(AppError error) {
    _isDisplayingError = true;
    _errorController.add(error);
  }

  /// Dispose the controller (called during app teardown).
  void dispose() {
    _errorController.close();
    _pendingErrors.clear();
  }
}
