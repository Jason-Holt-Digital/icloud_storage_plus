import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

void main() {
  group('typed exception constructors', () {
    const fields = (
      operation: 'readInPlace',
      retryable: true,
      message: 'Native failure',
      relativePath: 'Documents/file.txt',
      pathKind: 'containerRelative',
      nativeDomain: 'NSCocoaErrorDomain',
      nativeCode: 42,
      nativeDescription: 'Description',
      underlying: 'Underlying',
    );

    test('constructs each advertised subtype directly', () {
      final exceptions = <ICloudOperationException>[
        ICloudItemNotFoundException(
          operation: fields.operation,
          retryable: fields.retryable,
          message: fields.message,
          relativePath: fields.relativePath,
          pathKind: fields.pathKind,
          nativeDomain: fields.nativeDomain,
          nativeCode: fields.nativeCode,
          nativeDescription: fields.nativeDescription,
          underlying: fields.underlying,
        ),
        ICloudContainerAccessException(
          operation: fields.operation,
          retryable: fields.retryable,
          message: fields.message,
        ),
        ICloudConflictException(
          operation: fields.operation,
          retryable: fields.retryable,
          message: fields.message,
        ),
        ICloudCoordinationException(
          operation: fields.operation,
          retryable: fields.retryable,
          message: fields.message,
        ),
        ICloudInvalidArgumentException(
          operation: fields.operation,
          retryable: fields.retryable,
          message: fields.message,
        ),
        ICloudUnknownNativeException(
          operation: fields.operation,
          retryable: fields.retryable,
          message: fields.message,
        ),
      ];

      expect(exceptions.map((exception) => exception.category), [
        'itemNotFound',
        'containerAccess',
        'conflict',
        'coordination',
        'invalidArgument',
        'unknownNative',
      ]);
    });

    test('preserves normalized fields', () {
      final exception = ICloudItemNotFoundException(
        operation: fields.operation,
        retryable: fields.retryable,
        message: fields.message,
        relativePath: fields.relativePath,
        pathKind: fields.pathKind,
        nativeDomain: fields.nativeDomain,
        nativeCode: fields.nativeCode,
        nativeDescription: fields.nativeDescription,
        underlying: fields.underlying,
      );

      expect(exception.operation, fields.operation);
      expect(exception.retryable, fields.retryable);
      expect(exception.relativePath, fields.relativePath);
      expect(exception.pathKind, fields.pathKind);
      expect(exception.nativeDomain, fields.nativeDomain);
      expect(exception.nativeCode, fields.nativeCode);
      expect(exception.nativeDescription, fields.nativeDescription);
      expect(exception.underlying, fields.underlying);
    });
  });
}
