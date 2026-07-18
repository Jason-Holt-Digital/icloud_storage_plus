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

  /// Creates a typed method-channel contract failure.
  const ICloudOperationException.pluginContract({
    required String operation,
    required String message,
    Object? underlying,
  }) : this(
          category: 'pluginContract',
          operation: operation,
          retryable: false,
          message: message,
          underlying: underlying,
        );

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
  /// Creates an item-not-found exception from normalized failure fields.
  const ICloudItemNotFoundException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.pathKind,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'itemNotFound');
}

/// Thrown when the iCloud container cannot be accessed.
class ICloudContainerAccessException extends ICloudOperationException {
  /// Creates a container-access exception from normalized failure fields.
  const ICloudContainerAccessException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.pathKind,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'containerAccess');
}

/// Thrown when a version-exposure primitive (enumerate / copy-out /
/// mark-resolved) fails. The plugin only EXPOSES `NSFileVersion`s; it never
/// auto-resolves or silently deletes losing versions, so this exception never
/// represents an auto-resolved outcome.
class ICloudConflictException extends ICloudOperationException {
  /// Creates a conflict exception from normalized failure fields.
  const ICloudConflictException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.pathKind,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'conflict');
}

/// Thrown when file coordination fails for another reason.
class ICloudCoordinationException extends ICloudOperationException {
  /// Creates a coordination exception from normalized failure fields.
  const ICloudCoordinationException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.pathKind,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'coordination');
}

/// Thrown when native code reports invalid write-path arguments.
class ICloudInvalidArgumentException extends ICloudOperationException {
  /// Creates an invalid-argument exception from normalized failure fields.
  const ICloudInvalidArgumentException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.pathKind,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'invalidArgument');
}

/// Thrown when native code reports an unknown structured failure.
class ICloudUnknownNativeException extends ICloudOperationException {
  /// Creates an unknown-native exception from normalized failure fields.
  const ICloudUnknownNativeException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.pathKind,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'unknownNative');
}
