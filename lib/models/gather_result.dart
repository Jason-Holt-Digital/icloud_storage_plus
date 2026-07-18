import 'package:icloud_storage_plus/models/icloud_file.dart';

/// Result of a gather operation.
///
/// Malformed native payloads fail the gather call or update stream with a
/// typed plugin-contract exception rather than returning partial results.
class GatherResult {
  /// Creates a gather result containing the complete parsed file list.
  const GatherResult({required this.files});

  /// Parsed file metadata entries.
  final List<ICloudFile> files;
}
