/// Pure domain interface for error reporting.
///
/// Implemented by [ErrorService] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
abstract class IErrorService {
  void report(Object error, {String? message, StackTrace? stackTrace});
}
