import 'package:flutter/services.dart';

/// A failure reported by the CloudKit sync bridge.
final class CloudKitSyncException implements Exception {
  /// Creates a CloudKitSyncException.
  const CloudKitSyncException({
    required this.code,
    this.message,
    this.nativeDomain,
    this.nativeCode,
  });

  /// Converts a channel failure.
  factory CloudKitSyncException.fromPlatformException(
    PlatformException exception,
  ) {
    final details = exception.details;
    return CloudKitSyncException(
      code: exception.code,
      message: exception.message,
      nativeDomain: details is Map ? details['domain'] as String? : null,
      nativeCode: details is Map ? details['code'] as int? : null,
    );
  }

  /// A CloudKit or Foundation error; see [nativeDomain] and [nativeCode].
  static const nativeError = 'nativeError';

  /// The engine was never started, or it stopped. [message] says why.
  static const engineNotRunning = 'engineNotRunning';

  /// The state passed to start could not be decoded.
  static const invalidStateSerialization = 'invalidStateSerialization';

  /// An argument broke the bridge's contract.
  static const invalidArgument = 'invalidArgument';

  /// The downloaded record has no asset in the requested field.
  static const missingAsset = 'missingAsset';

  /// The OS is older than iOS 17 or macOS 14.
  static const unsupportedPlatformVersion = 'unsupportedPlatformVersion';

  /// One of the codes above.
  final String code;

  /// Description of the failure.
  final String? message;

  /// Native error domain for [nativeError], such as `CKErrorDomain`.
  final String? nativeDomain;

  /// Native error code for [nativeError], such as a `CKError.Code` raw value.
  final int? nativeCode;

  @override
  String toString() => 'CloudKitSyncException($code, $message'
      '${nativeDomain == null ? '' : ', $nativeDomain $nativeCode'})';
}
