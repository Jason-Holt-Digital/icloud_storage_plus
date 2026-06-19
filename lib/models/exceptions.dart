import 'package:flutter/services.dart';

/// An exception class used for development. It's used when invalid argument
/// is passed to the API
class InvalidArgumentException implements Exception {
  /// Constructor takes the exception message as an argument
  InvalidArgumentException(this._message);
  final String _message;

  /// Method to print the error message
  @override
  String toString() => 'InvalidArgumentException: $_message';
}

/// A class contains the error code from PlatformException
class PlatformExceptionCode {
  /// The code indicates iCloud container ID is not valid, or user is not signed
  /// in to iCloud, or user denied iCloud permission for this app
  static const String iCloudConnectionOrPermission = 'E_CTR';

  /// The code indicates a version-exposure failure (conflict enumeration,
  /// copy-out, or mark-resolved). The auto-resolve producer that previously
  /// emitted this code has been removed; the plugin only exposes versions
  /// and never auto-resolves-and-deletes losing versions.
  static const String conflict = 'E_CONFLICT';

  /// The code indicates file coordination failed.
  static const String coordination = 'E_COORDINATION';

  /// The code indicates file not found
  static const String fileNotFound = 'E_FNF';

  /// The code indicates file not found during a read operation
  static const String fileNotFoundRead = 'E_FNF_READ';

  /// The code indicates file not found during a write operation
  static const String fileNotFoundWrite = 'E_FNF_WRITE';

  /// The code indicates other error from native code
  static const String nativeCodeError = 'E_NAT';

  /// The code indicates invalid arguments were passed to a native method
  static const String argumentError = 'E_ARG';

  /// The code indicates a file read operation failed
  static const String readError = 'E_READ';

  /// The code indicates an operation was canceled
  static const String canceled = 'E_CANCEL';

  /// The code indicates an internal plugin error occurred in Dart code
  /// This represents a bug in the plugin. Please open a GitHub issue if you
  /// encounter this error.
  static const String pluginInternal = 'E_PLUGIN_INTERNAL';

  /// The code indicates the plugin was not properly initialized on the native
  /// side.
  static const String initializationError = 'E_INIT';

  /// The code indicates the native layer sent an invalid event type
  /// This represents a bug in the plugin. Please open a GitHub issue if you
  /// encounter this error.
  static const String invalidEvent = 'E_INVALID_EVENT';
}

/// Base class for typed iCloud operation failures surfaced from native code.
class ICloudOperationException implements Exception {
  /// Creates a typed iCloud operation exception.
  const ICloudOperationException({
    required this.category,
    required this.operation,
    required this.retryable,
    required this.message,
    this.relativePath,
    this.pathKind,
    this.nativeDomain,
    this.nativeCode,
    this.nativeDescription,
    this.underlying,
  });

  /// Stable error category from the native payload.
  final String category;

  /// Operation name that failed.
  final String operation;

  /// Whether retrying the operation may succeed.
  final bool retryable;

  /// Human-readable failure message.
  final String message;

  /// Relative path associated with the failure, when present.
  final String? relativePath;

  /// Non-PII classification of the native path involved in the failure.
  final String? pathKind;

  /// Native error domain, when present.
  final String? nativeDomain;

  /// Native error code, when present.
  final int? nativeCode;

  /// Native error description, when present.
  final String? nativeDescription;

  /// Underlying native error payload, when present.
  final Object? underlying;

  @override
  String toString() => '$category: $message';
}

/// Thrown when the requested item does not exist.
class ICloudItemNotFoundException extends ICloudOperationException {
  /// Creates an item-not-found exception.
  ICloudItemNotFoundException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          pathKind: data.pathKind,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

/// Thrown when the iCloud container cannot be accessed.
class ICloudContainerAccessException extends ICloudOperationException {
  /// Creates a container-access exception.
  ICloudContainerAccessException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          pathKind: data.pathKind,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

/// Thrown when a version-exposure primitive (enumerate / copy-out /
/// mark-resolved) fails. The plugin only EXPOSES `NSFileVersion`s; it never
/// auto-resolves or silently deletes losing versions, so this exception never
/// represents an auto-resolved outcome.
class ICloudConflictException extends ICloudOperationException {
  /// Creates a conflict exception.
  ICloudConflictException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          pathKind: data.pathKind,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

/// Thrown when file coordination fails for another reason.
class ICloudCoordinationException extends ICloudOperationException {
  /// Creates a coordination exception.
  ICloudCoordinationException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          pathKind: data.pathKind,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

/// Thrown when native code reports invalid write-path arguments.
class ICloudInvalidArgumentException extends ICloudOperationException {
  /// Creates an invalid-argument exception.
  ICloudInvalidArgumentException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          pathKind: data.pathKind,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

/// Thrown when native code reports an unknown structured failure.
class ICloudUnknownNativeException extends ICloudOperationException {
  /// Creates an unknown native exception.
  ICloudUnknownNativeException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          pathKind: data.pathKind,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

/// Maps a structured platform exception into a typed iCloud exception.
ICloudOperationException mapICloudPlatformException(PlatformException error) {
  final details = error.details;
  final payload = details is Map ? details : const <Object?, Object?>{};
  final data = _ICloudOperationExceptionData(
    category: _readString(payload, 'category') ?? 'unknownNative',
    operation: _readString(payload, 'operation') ?? 'unknown',
    retryable: payload['retryable'] == true,
    message: error.message ?? 'iCloud operation failed',
    relativePath: _readString(payload, 'relativePath'),
    pathKind: _readString(payload, 'pathKind'),
    nativeDomain: _readString(payload, 'nativeDomain'),
    nativeCode: _readInt(payload, 'nativeCode'),
    nativeDescription: _readString(payload, 'nativeDescription'),
    underlying: payload['underlying'],
  );

  return switch (data.category) {
    'itemNotFound' => ICloudItemNotFoundException._(data),
    'containerAccess' => ICloudContainerAccessException._(data),
    'conflict' => ICloudConflictException._(data),
    'coordination' => ICloudCoordinationException._(data),
    'invalidArgument' => ICloudInvalidArgumentException._(data),
    _ => ICloudUnknownNativeException._(data),
  };
}

class _ICloudOperationExceptionData {
  const _ICloudOperationExceptionData({
    required this.category,
    required this.operation,
    required this.retryable,
    required this.message,
    this.relativePath,
    this.pathKind,
    this.nativeDomain,
    this.nativeCode,
    this.nativeDescription,
    this.underlying,
  });

  final String category;
  final String operation;
  final bool retryable;
  final String message;
  final String? relativePath;
  final String? pathKind;
  final String? nativeDomain;
  final int? nativeCode;
  final String? nativeDescription;
  final Object? underlying;
}

String? _readString(Map<Object?, Object?> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

int? _readInt(Map<Object?, Object?> payload, String key) {
  final value = payload[key];
  return value is int ? value : null;
}
