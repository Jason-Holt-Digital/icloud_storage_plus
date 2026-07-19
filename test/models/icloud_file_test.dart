import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';

void main() {
  group('ICloudFile equality', () {
    test('files with identical properties are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/test.txt',
        'sizeInBytes': 1024,
        'creationDate': 1609459200.0, // 2021-01-01 00:00:00 UTC
        'contentChangeDate': 1609545600.0, // 2021-01-02 00:00:00 UTC
        'downloadStatus': 'current',
        'isUploaded': true,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/test.txt',
        'sizeInBytes': 1024,
        'creationDate': 1609459200.0,
        'contentChangeDate': 1609545600.0,
        'downloadStatus': 'current',
        'isUploaded': true,
      });

      expect(file1, equals(file2));
      expect(file1 == file2, isTrue);
    });

    test('files with different relativePath are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/test.txt',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/other.txt',
      });

      expect(file1, isNot(equals(file2)));
      expect(file1 == file2, isFalse);
    });

    test('files with different isDirectory are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/item',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/item',
        'isDirectory': true,
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different sizeInBytes are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 2048,
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different creationDate are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'creationDate': 1609459200.0,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'creationDate': 1609545600.0,
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different contentChangeDate are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'contentChangeDate': 1609459200.0,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'contentChangeDate': 1609545600.0,
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different isDownloading are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'isDownloading': true,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different downloadStatus are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'current',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'downloaded',
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different isUploading are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'isUploading': true,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different isUploaded are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'isUploaded': true,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with different hasUnresolvedConflicts are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'hasUnresolvedConflicts': true,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      expect(file1, isNot(equals(file2)));
    });

    test('files with null vs non-null optional properties are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': null,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      expect(file1, isNot(equals(file2)));
    });

    test('throws when relativePath is missing or not a string', () {
      expect(
        () => ICloudFile.fromMap(const {
          'relativePath': null,
        }),
        throwsException,
      );

      expect(
        () => ICloudFile.fromMap(const {
          'relativePath': 123,
        }),
        throwsException,
      );
    });
  });

  group('ICloudFile hashCode', () {
    test('equal files have equal hashCodes', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/test.txt',
        'sizeInBytes': 1024,
        'creationDate': 1609459200.0,
        'contentChangeDate': 1609545600.0,
        'downloadStatus': 'current',
        'isUploaded': true,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'Documents/test.txt',
        'sizeInBytes': 1024,
        'creationDate': 1609459200.0,
        'contentChangeDate': 1609545600.0,
        'downloadStatus': 'current',
        'isUploaded': true,
      });

      expect(file1.hashCode, equals(file2.hashCode));
    });

    test('hashCode is consistent across multiple calls', () {
      final file = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      final hash1 = file.hashCode;
      final hash2 = file.hashCode;
      final hash3 = file.hashCode;

      expect(hash1, equals(hash2));
      expect(hash2, equals(hash3));
    });
  });

  group('ICloudFile equality contract', () {
    test('reflexive: file equals itself', () {
      final file = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      expect(file, equals(file));
      expect(file == file, isTrue);
    });

    test('symmetric: if a == b then b == a', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      expect(file1 == file2, isTrue);
      expect(file2 == file1, isTrue);
    });

    test('transitive: if a == b and b == c then a == c', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      final file3 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': 1024,
      });

      expect(file1 == file2, isTrue);
      expect(file2 == file3, isTrue);
      expect(file1 == file3, isTrue);
    });

    test('consistent: multiple calls to == return same result', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      final result1 = file1 == file2;
      final result2 = file1 == file2;
      final result3 = file1 == file2;

      expect(result1, equals(result2));
      expect(result2, equals(result3));
    });

    test('null comparison: file does not equal null', () {
      final file = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      // This tests the Equatable == operator implementation
      expect(file, isNot(equals(null)));
    });
  });

  group('ICloudFile equality with nullable properties', () {
    test('files with both null sizeInBytes are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': null,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'sizeInBytes': null,
      });

      expect(file1, equals(file2));
    });

    test('files with both null creationDate are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'creationDate': null,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'creationDate': null,
      });

      expect(file1, equals(file2));
    });

    test('files with both null contentChangeDate are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'contentChangeDate': null,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'contentChangeDate': null,
      });

      expect(file1, equals(file2));
    });

    test('files with both null downloadStatus are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': null,
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': null,
      });

      expect(file1, equals(file2));
    });

    test('files with all properties null except relativePath are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
      });

      expect(file1, equals(file2));
      expect(file1.hashCode, equals(file2.hashCode));
    });
  });

  group('ICloudFile equality with DownloadStatus enum', () {
    test('files with same DownloadStatus.current are equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'current',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'current',
      });

      expect(file1, equals(file2));
      expect(file1.downloadStatus, equals(DownloadStatus.current));
      expect(file2.downloadStatus, equals(DownloadStatus.current));
    });

    test('files with DownloadStatus.current vs downloaded are not equal', () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'current',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'downloaded',
      });

      expect(file1, isNot(equals(file2)));
      expect(file1.downloadStatus, equals(DownloadStatus.current));
      expect(file2.downloadStatus, equals(DownloadStatus.downloaded));
    });

    test('files with DownloadStatus.downloaded vs notDownloaded are not equal',
        () {
      final file1 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'downloaded',
      });

      final file2 = ICloudFile.fromMap(const {
        'relativePath': 'test.txt',
        'downloadStatus': 'notDownloaded',
      });

      expect(file1, isNot(equals(file2)));
      expect(file1.downloadStatus, equals(DownloadStatus.downloaded));
      expect(file2.downloadStatus, equals(DownloadStatus.notDownloaded));
    });
  });
}
