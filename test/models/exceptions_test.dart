import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

void main() {
  group('mapICloudPlatformException', () {
    PlatformException buildError(String? category) {
      return PlatformException(
        code: PlatformExceptionCode.nativeCodeError,
        message: 'Native failure',
        details: {
          if (category != null) 'category': category,
          'operation': 'readInPlace',
          'retryable': true,
          'relativePath': 'Documents/file.txt',
          'pathKind': 'containerRelative',
          'nativeDomain': 'NSCocoaErrorDomain',
          'nativeCode': 42,
          'nativeDescription': 'Description',
          'underlying': 'Underlying',
        },
      );
    }

    test('maps conflict category to ICloudConflictException', () {
      final exception = mapICloudPlatformException(buildError('conflict'));

      expect(exception, isA<ICloudConflictException>());
    });

    test('preserves non-PII native path kind enrichment', () {
      final exception = mapICloudPlatformException(buildError('unknownNative'));

      expect(exception.pathKind, 'containerRelative');
      expect(exception.nativeDomain, 'NSCocoaErrorDomain');
      expect(exception.nativeCode, 42);
    });

    test('maps itemNotFound category to ICloudItemNotFoundException', () {
      final exception = mapICloudPlatformException(buildError('itemNotFound'));

      expect(exception, isA<ICloudItemNotFoundException>());
    });

    test(
      'maps containerAccess category to ICloudContainerAccessException',
      () {
        final exception = mapICloudPlatformException(
          buildError('containerAccess'),
        );

        expect(exception, isA<ICloudContainerAccessException>());
      },
    );

    test('maps timeout category to ICloudTimeoutException', () {
      final exception = mapICloudPlatformException(buildError('timeout'));

      expect(exception, isA<ICloudTimeoutException>());
    });

    test(
      'maps itemNotDownloaded category to '
      'ICloudItemNotDownloadedException',
      () {
        final exception = mapICloudPlatformException(
          buildError('itemNotDownloaded'),
        );

        expect(exception, isA<ICloudItemNotDownloadedException>());
      },
    );

    test(
      'maps downloadInProgress category to '
      'ICloudDownloadInProgressException',
      () {
        final exception = mapICloudPlatformException(
          buildError('downloadInProgress'),
        );

        expect(exception, isA<ICloudDownloadInProgressException>());
      },
    );

    test(
      'maps explicit coordination category to ICloudCoordinationException',
      () {
        final exception = mapICloudPlatformException(
          buildError('coordination'),
        );

        expect(exception, isA<ICloudCoordinationException>());
      },
    );

    test(
      'maps invalidArgument category to ICloudInvalidArgumentException',
      () {
        final exception = mapICloudPlatformException(
          buildError('invalidArgument'),
        );

        expect(exception, isA<ICloudInvalidArgumentException>());
      },
    );

    test(
      'maps missing category to ICloudUnknownNativeException',
      () {
        final exception = mapICloudPlatformException(buildError(null));

        expect(exception, isA<ICloudUnknownNativeException>());
      },
    );

    test(
      'maps unknown category to ICloudUnknownNativeException',
      () {
        final exception = mapICloudPlatformException(
          buildError('somethingElse'),
        );

        expect(exception, isA<ICloudUnknownNativeException>());
      },
    );
  });
}
