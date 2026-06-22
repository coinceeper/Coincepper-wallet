import 'package:flutter/foundation.dart';

/// Types of errors that can occur in the app
enum ErrorType {
  network,
  server,
  timeout,
  validation,
  auth,
  duplicate,
  general,
}

/// A structured error model that carries user-facing information
/// and optional technical details / retry callback.
class AppError {
  final String message;
  final String? title;
  final ErrorType type;
  final String? technicalDetails;
  final VoidCallback? onRetry;

  AppError({
    required this.message,
    this.title,
    this.type = ErrorType.general,
    this.technicalDetails,
    this.onRetry,
  });

  /// Automatically detect the error type from a raw exception.
  factory AppError.fromException(
    Object error, {
    VoidCallback? onRetry,
    String? fallbackMessage,
  }) {
    final message = error.toString();
    final type = _detectType(message);
    final userMessage = _toUserMessage(message, type, fallbackMessage);
    final title = _toTitle(type);

    return AppError(
      message: userMessage,
      title: title,
      type: type,
      technicalDetails: kDebugMode ? message : null,
      onRetry: onRetry,
    );
  }

  /// Create an error specifically for network failures.
  factory AppError.network({
    required String message,
    String? technicalDetails,
    VoidCallback? onRetry,
  }) {
    return AppError(
      message: message,
      title: 'Network Error',
      type: ErrorType.network,
      technicalDetails: technicalDetails,
      onRetry: onRetry,
    );
  }

  /// Create a general error with a user-friendly message.
  factory AppError.general({
    required String message,
    String? title,
    String? technicalDetails,
    VoidCallback? onRetry,
  }) {
    return AppError(
      message: message,
      title: title,
      type: ErrorType.general,
      technicalDetails: technicalDetails,
      onRetry: onRetry,
    );
  }

  static ErrorType _detectType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('internet') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('connectivity') ||
        lower.contains('dioexception')) {
      return ErrorType.network;
    }
    if (lower.contains('server') ||
        lower.contains('cloudflare') ||
        lower.contains('security') ||
        lower.contains('status code') ||
        lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503')) {
      return ErrorType.server;
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return ErrorType.timeout;
    }
    if (lower.contains('already been imported') ||
        lower.contains('duplicate') ||
        lower.contains('exists') ||
        lower.contains('already exist')) {
      return ErrorType.duplicate;
    }
    if (lower.contains('invalid') ||
        lower.contains('incorrect') ||
        lower.contains('wrong') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden')) {
      return ErrorType.validation;
    }
    return ErrorType.general;
  }

  static String _toUserMessage(String raw, ErrorType type, String? fallback) {
    if (fallback != null) return fallback;
    switch (type) {
      case ErrorType.network:
        return 'Unable to connect to the server. Please check your internet connection and try again.';
      case ErrorType.server:
        return 'The server is experiencing issues. Please try again later.';
      case ErrorType.timeout:
        return 'The request timed out. Please check your connection and try again.';
      case ErrorType.validation:
        return 'Invalid input. Please check your entries and try again.';
      case ErrorType.auth:
        return 'Authentication failed. Please try again.';
      case ErrorType.duplicate:
        return 'This item already exists.';
      case ErrorType.general:
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  static String _toTitle(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return 'Connection Error';
      case ErrorType.server:
        return 'Server Error';
      case ErrorType.timeout:
        return 'Request Timed Out';
      case ErrorType.validation:
        return 'Invalid Input';
      case ErrorType.auth:
        return 'Authentication Error';
      case ErrorType.duplicate:
        return 'Already Exists';
      case ErrorType.general:
      default:
        return 'Error';
    }
  }

  @override
  String toString() => 'AppError($type): $message';
}
