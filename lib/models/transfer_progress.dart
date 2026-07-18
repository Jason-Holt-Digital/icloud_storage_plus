/// The state of a transfer progress stream event.
enum ICloudTransferProgressType {
  /// A progress update, where [ICloudTransferProgress.percent] is non-null.
  progress,

  /// The transfer finished successfully.
  done,
}

/// A typed data event emitted from upload/download progress streams.
///
/// Failures are delivered through the stream error channel as typed
/// `ICloudOperationException` values.
class ICloudTransferProgress {
  const ICloudTransferProgress._({
    required this.type,
    this.percent,
  });

  /// Creates a progress update event.
  const ICloudTransferProgress.progress(double percent)
      : this._(type: ICloudTransferProgressType.progress, percent: percent);

  /// Creates a completion event.
  const ICloudTransferProgress.done()
      : this._(type: ICloudTransferProgressType.done);

  /// The kind of data event.
  final ICloudTransferProgressType type;

  /// Upload/download progress as a percentage.
  ///
  /// This is only set when [type] is [ICloudTransferProgressType.progress].
  final double? percent;

  /// Whether this event represents a progress update.
  bool get isProgress => type == ICloudTransferProgressType.progress;

  /// Whether this event represents successful completion.
  bool get isDone => type == ICloudTransferProgressType.done;
}
