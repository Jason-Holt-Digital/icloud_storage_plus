import 'package:equatable/equatable.dart';

/// Typed event emitted when an observed iCloud document changes.
class ICloudDocumentChange extends Equatable {
  /// Creates a document change event.
  const ICloudDocumentChange({
    required this.relativePath,
    required this.kind,
  });

  /// Creates a document change event from the native event payload.
  factory ICloudDocumentChange.fromMap(Map<dynamic, dynamic> map) {
    final relativePath = map['relativePath'];
    if (relativePath is! String) {
      throw FormatException(
        'ICloudDocumentChange.fromMap expected String relativePath, '
        'got ${relativePath.runtimeType}',
      );
    }
    final kind = map['kind'];
    if (kind is! String) {
      throw FormatException(
        'ICloudDocumentChange.fromMap expected String kind, '
        'got ${kind.runtimeType}',
      );
    }

    return ICloudDocumentChange(
      relativePath: relativePath,
      kind: ICloudDocumentChangeKind.fromValue(kind),
    );
  }

  /// Relative path of the observed item inside the iCloud container.
  final String relativePath;

  /// Kind of document change observed by the native presenter.
  final ICloudDocumentChangeKind kind;

  @override
  List<Object?> get props => [relativePath, kind];
}

/// Stable event kinds emitted by the native document presenter bridge.
enum ICloudDocumentChangeKind {
  /// The existing `ICloudDocument` presenter observed a remote/item change.
  remoteChange('remoteChange'),

  /// The document entered a conflict state.
  conflict('conflict'),

  /// The document reported a saving error state.
  ///
  /// Emitted on iOS when `UIDocument` reports a saving error. macOS does not
  /// expose an equivalent `NSDocument` file-presenter state for this stream.
  savingError('savingError'),

  /// The document reported editing is disabled.
  ///
  /// Emitted on iOS when `UIDocument` reports editing is disabled. macOS does
  /// not expose an equivalent `NSDocument` file-presenter state for this
  /// stream.
  ///
  /// On iOS, `UIDocument`'s default `presentedItemDidChange` implementation
  /// temporarily sets `.editingDisabled` then clears it during a remote sync
  /// revert. An `editingDisabled` event may therefore be an implementation
  /// artifact of the revert mechanism rather than a genuine editing
  /// restriction imposed by the app or system.
  editingDisabled('editingDisabled'),

  /// The native payload contained an unknown kind.
  unknown('unknown');

  const ICloudDocumentChangeKind(this.value);

  /// Wire value sent over the event channel.
  final String value;

  /// Parses a native event kind string.
  ///
  /// Unrecognised values map to [ICloudDocumentChangeKind.unknown] for
  /// forward-compatibility with new kinds added in future native releases.
  static ICloudDocumentChangeKind fromValue(String value) {
    return ICloudDocumentChangeKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => ICloudDocumentChangeKind.unknown,
    );
  }
}
