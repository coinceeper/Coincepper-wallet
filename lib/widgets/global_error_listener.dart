import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_error.dart';
import '../services/error_service.dart';
import '../utils/secure_log.dart';
import '../di/service_locator.dart';
import 'beautiful_error_modal.dart';

/// A top-level widget that listens to [ErrorService.errorStream] and
/// displays errors to the user via [BeautifulErrorModal] when they occur.
///
/// Place this high in the widget tree (e.g. as a wrapper in the MaterialApp
/// builder) so it covers the entire app.
///
/// Architecture:
/// ```
/// MaterialApp.builder
///   └── NetworkOverlay
///        └── GlobalErrorListener    ← subscribes to ErrorService
///             └── child             ← the actual app content
/// ```
///
/// When an [AppError] arrives on the stream, this widget shows a modal
/// bottom sheet with error details and an optional "Try Again" button
/// wired to [AppError.onRetry].
class GlobalErrorListener extends StatefulWidget {
  final Widget child;

  const GlobalErrorListener({super.key, required this.child});

  @override
  State<GlobalErrorListener> createState() => _GlobalErrorListenerState();
}

class _GlobalErrorListenerState extends State<GlobalErrorListener> {
  StreamSubscription<AppError>? _errorSubscription;
  bool _isShowingError = false;

  @override
  void initState() {
    super.initState();
    _subscribeToErrors();
  }

  void _subscribeToErrors() {
    try {
      final errorService = ServiceLocator.get<ErrorService>();
      _errorSubscription = errorService.errorStream.listen(_onError);
    } catch (e) {
      SecureLog.w('GlobalErrorListener: ErrorService not ready, retrying in 2s', error: e);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _subscribeToErrors();
      });
    }
  }

  void _onError(AppError appError) {
    if (!mounted || _isShowingError) return;

    _isShowingError = true;

    _showErrorModal(appError).then((_) {
      if (mounted) {
        _isShowingError = false;
        try {
          ServiceLocator.get<ErrorService>().onErrorDismissed();
        } catch (e) {
          SecureLog.w('GlobalErrorListener: onErrorDismissed failed', error: e);
        }
      }
    });
  }

  Future<void> _showErrorModal(AppError appError) async {
    if (!mounted) return;

    await BeautifulErrorModal.show(
      context,
      title: appError.title ?? 'Error',
      message: appError.message,
      details: appError.technicalDetails,
      onRetry: appError.onRetry != null
          ? () => appError.onRetry?.call()
          : null,
    );
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
