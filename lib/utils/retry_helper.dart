import 'dart:async';

/// Configuration for retry behavior.
///
/// Controls how many times an operation is retried, the base delay between
/// retries, and the maximum total cumulative delay allowed across all retries.
class RetryConfig {
  final int maxRetries;
  final Duration baseDelay;
  final Duration? maxTotalDelay;

  const RetryConfig({
    required this.maxRetries,
    required this.baseDelay,
    this.maxTotalDelay,
  });
}

/// The result of a retry operation.
///
/// - [succeeded]: `true` if the operation completed without error.
/// - [data]: The value returned by the operation (present only if succeeded).
/// - [error]: The last error that occurred (present only if failed).
class RetryResult<T> {
  final bool succeeded;
  final T? data;
  final Exception? error;

  RetryResult._success(this.data)
      : succeeded = true,
        error = null;

  RetryResult._failure(this.error)
      : succeeded = false,
        data = null;
}

/// A utility class that provides a configurable retry mechanism with
/// exponential backoff for transient failures.
///
/// Usage:
/// ```dart
/// final result = await RetryHelper.retry<List>(
///   _performOperation,
///   config: RetryConfig(maxRetries: 3, baseDelay: Duration(seconds: 2)),
///   operationName: 'myOperation',
///   shouldRetry: (error) => error is SocketException,
///   onRetry: (attempt, delay) async { log('Retrying...'); },
///   onFinalFailure: (error, attempts) async { log('Failed'); },
/// );
///
/// if (result.succeeded) { use(result.data); }
/// ```
class RetryHelper {
  RetryHelper._();

  /// Execute [operation] with automatic retries on failure.
  ///
  /// Parameters:
  /// - [operation]: The async function to execute.
  /// - [config]: Configuration for retry count, delay, and total time limit.
  /// - [operationName]: A human-readable name for logging/tracking.
  /// - [shouldRetry]: A predicate that decides whether a given [Exception]
  ///   is transient and should be retried. If omitted, all exceptions are
  ///   considered transient.
  /// - [onRetry]: Called before each retry attempt with the attempt number
  ///   (1-based) and the delay that will be applied.
  /// - [onFinalFailure]: Called after all retries have been exhausted with
  ///   the last error and the total number of attempts made.
  ///
  /// Returns a [RetryResult<T>] indicating success or failure.
  static Future<RetryResult<T>> retry<T>(
    Future<T> Function() operation, {
    required RetryConfig config,
    String? operationName,
    bool Function(Exception error)? shouldRetry,
    Future<void> Function(int attempt, Duration delay)? onRetry,
    Future<void> Function(Exception lastError, int totalAttempts)?
        onFinalFailure,
  }) async {
    Exception? lastError;
    Duration totalDelay = Duration.zero;

    for (int attempt = 1; attempt <= config.maxRetries; attempt++) {
      try {
        final result = await operation();
        return RetryResult<T>._success(result);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());

        // If we've exhausted all retries, stop.
        if (attempt >= config.maxRetries) {
          break;
        }

        // If shouldRetry is provided and says we should NOT retry, stop.
        if (shouldRetry != null && !shouldRetry(lastError)) {
          break;
        }

        // Calculate delay with exponential backoff: baseDelay * 2^(attempt-1)
        final delayMultiplier = 1 << (attempt - 1); // 1, 2, 4, 8, ...
        Duration delay = Duration(
          milliseconds: config.baseDelay.inMilliseconds * delayMultiplier,
        );

        // If maxTotalDelay is set, cap the cumulative delay.
        if (config.maxTotalDelay != null) {
          final wouldExceed =
              totalDelay + delay > config.maxTotalDelay!;
          if (wouldExceed) {
            delay = config.maxTotalDelay! - totalDelay;
            if (delay <= Duration.zero) {
              // No time left for any meaningful delay, stop now.
              break;
            }
          }
        }

        totalDelay += delay;

        // Notify caller about the retry.
        if (onRetry != null) {
          await onRetry(attempt, delay);
        }

        await Future.delayed(delay);
      }
    }

    // All retries exhausted — notify caller.
    final finalError =
        lastError ?? Exception('Operation failed after retries');

    if (onFinalFailure != null) {
      await onFinalFailure(finalError, config.maxRetries);
    }

    return RetryResult<T>._failure(finalError);
  }
}
