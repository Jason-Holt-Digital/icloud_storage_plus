/// Download status of an iCloud item.
enum DownloadStatus {
  /// This item has not been downloaded yet.
  notDownloaded,

  /// There is a local version of this item available.
  downloaded,

  /// The local version is current on this device.
  current,
}

/// Parses the normalized download-status wire values.
DownloadStatus? parseDownloadStatus(String? value) => switch (value) {
      null => null,
      'notDownloaded' => DownloadStatus.notDownloaded,
      'downloaded' => DownloadStatus.downloaded,
      'current' => DownloadStatus.current,
      _ => throw FormatException('Unsupported downloadStatus: $value'),
    };
