import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/models/icloud_item_metadata.dart';

void main() {
  group('ICloudItemMetadata.fromMap', () {
    test('normalizes typed metadata fields from a map', () {
      final metadata = ICloudItemMetadata.fromMap(const {
        'relativePath': 'Documents/report.txt',
        'isDirectory': false,
        'sizeInBytes': 1024,
        'creationDate': 1609459200.0,
        'contentChangeDate': 1609545600.0,
        'downloadStatus': 'current',
        'isDownloading': false,
        'isUploading': true,
        'isUploaded': true,
        'hasUnresolvedConflicts': false,
      });

      expect(metadata.relativePath, 'Documents/report.txt');
      expect(metadata.isDirectory, isFalse);
      expect(metadata.sizeInBytes, 1024);
      expect(
        metadata.creationDate,
        DateTime.fromMillisecondsSinceEpoch(1609459200000),
      );
      expect(
        metadata.contentChangeDate,
        DateTime.fromMillisecondsSinceEpoch(1609545600000),
      );
      expect(metadata.downloadStatus, DownloadStatus.current);
      expect(metadata.isDownloading, isFalse);
      expect(metadata.isUploading, isTrue);
      expect(metadata.isUploaded, isTrue);
      expect(metadata.hasUnresolvedConflicts, isFalse);
      expect(metadata.isLocal, isTrue);
    });

    test('derives isLocal for current status', () {
      final metadata = ICloudItemMetadata.fromMap(const {
        'relativePath': 'Documents/report.txt',
        'downloadStatus': 'current',
      });

      expect(metadata.isLocal, isTrue);
    });

    test('maps normalized notDownloaded status', () {
      final metadata = ICloudItemMetadata.fromMap(const {
        'relativePath': 'Documents/report.txt',
        'downloadStatus': 'notDownloaded',
      });

      expect(metadata.downloadStatus, DownloadStatus.notDownloaded);
      expect(metadata.isLocal, isFalse);
    });

    test('rejects present optional fields with the wrong type', () {
      expect(
        () => ICloudItemMetadata.fromMap(const {
          'relativePath': 'Documents/report.txt',
          'isUploaded': 'yes',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
