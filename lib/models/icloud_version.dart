import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/src/native_payload.dart';

/// A descriptor for a single unresolved `NSFileVersion` conflict version,
/// surfaced from the native layer via the version-exposure primitives.
///
/// The plugin only EXPOSES versions; it never auto-resolves or deletes
/// losing versions. The app owns conflict policy: it enumerates
/// unresolved versions, copies losing versions out to badged backups,
/// and marks conflicts resolved only after backups are confirmed.
///
/// [identifier] is opaque and round-trippable: pass it back to
/// `ICloudStorage.copyConflictVersion` to select this version for
/// copy-out. [modificationDate] is the version's modification timestamp
/// (null when the platform does not provide one).
class ICloudVersion extends Equatable {
  /// Creates an [ICloudVersion] directly.
  const ICloudVersion({
    required this.identifier,
    this.modificationDate,
  });

  /// Creates an [ICloudVersion] from the platform-channel payload.
  ICloudVersion.fromMap(Map<dynamic, dynamic> map)
      : identifier = nativeRequireString(map, 'identifier'),
        modificationDate = nativeSecondsNumberToDateTime(
          nativeReadNullableNum(map, 'modificationDate'),
        );

  /// Opaque, round-trippable identifier for the version. Pass back to
  /// `ICloudStorage.copyConflictVersion` to select this version.
  final String identifier;

  /// The version's modification date, when available.
  final DateTime? modificationDate;

  @override
  List<Object?> get props => [identifier, modificationDate];
}
