import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Document storage and the CloudKit sync bridge stay separate: neither
/// imports the other, and the bridge never touches the ubiquity container.
void main() {
  final bridgeDart = [
    File('lib/cloudkit_sync.dart'),
    ...Directory('lib/src/cloudkit_sync').listSync().whereType<File>(),
  ];
  final documentDart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !bridgeDart.any((bridge) => bridge.path == file.path));

  Iterable<String> imports(File file) => file.readAsLinesSync().where(
        (line) => line.startsWith('import ') || line.startsWith('export '),
      );

  test('bridge Dart files import only bridge files and SDK packages', () {
    for (final file in bridgeDart) {
      for (final line in imports(file)) {
        final isPackageImport = line.contains("'package:icloud_storage_plus/");
        final isRelative =
            !line.contains("'package:") && !line.contains("'dart:");
        expect(
          !isPackageImport ||
              line.contains("'package:icloud_storage_plus/src/cloudkit_sync/"),
          isTrue,
          reason: '${file.path}: $line',
        );
        expect(
          !isRelative || line.contains('src/cloudkit_sync/'),
          isTrue,
          reason: '${file.path}: $line',
        );
      }
    }
  });

  test('document storage Dart files do not import the bridge', () {
    for (final file in documentDart) {
      for (final line in imports(file)) {
        expect(line, isNot(contains('cloudkit_sync')), reason: file.path);
      }
    }
  });

  test('iOS and macOS bridge Swift sources and tests are identical', () {
    const ios = 'ios/icloud_storage_plus/Sources/icloud_storage_plus_cloudkit';
    const macos =
        'macos/icloud_storage_plus/Sources/icloud_storage_plus_cloudkit';
    List<File> files(String root) => Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !file.path.contains('/.build/'))
        .toList();
    final iosFiles = files(ios);
    expect(iosFiles, isNotEmpty);
    expect(files(macos), hasLength(iosFiles.length));
    for (final file in iosFiles) {
      final counterpart = File(file.path.replaceFirst(ios, macos));
      expect(
        counterpart.readAsBytesSync(),
        file.readAsBytesSync(),
        reason: '${counterpart.path} differs from ${file.path}',
      );
    }
  });

  for (final platform in ['ios', 'macos']) {
    final sources = '$platform/icloud_storage_plus/Sources';

    test('$platform bridge Swift files do not use the ubiquity container', () {
      final files = Directory('$sources/icloud_storage_plus_cloudkit')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.swift'));
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
          file.readAsStringSync().toLowerCase(),
          isNot(contains('ubiquit')),
          reason: file.path,
        );
      }
    });

    test(
        '$platform document storage Swift refers to the bridge only to '
        'register it', () {
      final references = [
        for (final directory in [
          'icloud_storage_plus',
          'icloud_storage_plus_foundation',
        ])
          for (final file in Directory('$sources/$directory')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.swift')))
            for (final line in file.readAsLinesSync())
              if (line.contains('CloudKit')) line.trim(),
      ];
      expect(references, [
        '// CloudKit sync bridge: a separate module with its own channel.',
        'CloudKitSyncChannel.register(with: registrar)',
      ]);
    });
  }
}
