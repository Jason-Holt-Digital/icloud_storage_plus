// Internal helpers are public only across package library boundaries.
// ignore_for_file: public_member_api_docs

import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

ICloudOperationException decodePlatformException(PlatformException error) {
  final details = error.details;
  final payload = details is Map ? details : const <Object?, Object?>{};
  final operation = _readString(payload, 'operation') ?? 'unknown';
  final retryable = payload['retryable'] == true;
  final message = error.message ?? 'iCloud operation failed';
  final relativePath = _readString(payload, 'relativePath');
  final pathKind = _readString(payload, 'pathKind');
  final nativeDomain = _readString(payload, 'nativeDomain');
  final nativeCode = _readInt(payload, 'nativeCode');
  final nativeDescription = _readString(payload, 'nativeDescription');
  final underlying = payload['underlying'];
  final nativeErrorChain = _readNativeErrorChain(payload['nativeErrorChain']);
  final category = _readString(payload, 'category');

  return switch (category) {
    'itemNotFound' => ICloudItemNotFoundException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    'containerAccess' => ICloudContainerAccessException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    'conflict' => ICloudConflictException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    'coordination' => ICloudCoordinationException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    'invalidArgument' => ICloudInvalidArgumentException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    'cancelled' => ICloudCancelledException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    'initialization' => ICloudInitializationException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    null || 'unknownNative' => ICloudUnknownNativeException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
    final String otherCategory => ICloudOperationException(
        category: otherCategory,
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
        nativeErrorChain: nativeErrorChain,
      ),
  };
}

String? _readString(Map<Object?, Object?> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

int? _readInt(Map<Object?, Object?> payload, String key) {
  final value = payload[key];
  return value is int ? value : null;
}

List<ICloudNativeError> _readNativeErrorChain(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is Map && entry['domain'] is String && entry['code'] is int)
        ICloudNativeError(
          domain: entry['domain'] as String,
          code: entry['code'] as int,
          pluginReason: entry['pluginReason'] is String
              ? entry['pluginReason'] as String
              : null,
        ),
  ];
}
