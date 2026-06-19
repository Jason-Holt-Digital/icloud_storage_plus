import 'package:equatable/equatable.dart';

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

  /// Creates an [ICloudVersion] from a platform channel map.
  ///
  /// Used internally by the method channel layer to deserialize native
  /// results. Expected keys: `identifier` (String, required),
  /// `modificationDate` (num?, optional).
  ICloudVersion.fromMap(Map<dynamic, dynamic> map)
      : identifier = _requireIdentifier(map),
        modificationDate = _mapToDateTime(map['modificationDate']);

  /// Opaque, round-trippable identifier for the version. Pass back to
  /// `ICloudStorage.copyConflictVersion` to select this version.
  final String identifier;

  /// The version's modification date, when available.
  final DateTime? modificationDate;

  static String _requireIdentifier(Map<dynamic, dynamic> map) {
    final value = map['identifier'];
    if (value is String) return value;
    throw FormatException(
      'identifier is required and must be a String '
      '(got: ${value.runtimeType})',
    );
  }

  static DateTime? _mapToDateTime(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    return null;
  }

  @override
  List<Object?> get props => [identifier, modificationDate];
}
