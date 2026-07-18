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

  return switch (_readString(payload, 'category')) {
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
      ),
    _ => ICloudUnknownNativeException(
        operation: operation,
        retryable: retryable,
        message: message,
        relativePath: relativePath,
        pathKind: pathKind,
        nativeDomain: nativeDomain,
        nativeCode: nativeCode,
        nativeDescription: nativeDescription,
        underlying: underlying,
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
