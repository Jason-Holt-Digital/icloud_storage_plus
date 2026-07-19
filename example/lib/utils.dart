import 'package:icloud_storage_plus/icloud_storage.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

String getErrorMessage(Object? ex) {
  if (ex is ICloudOperationException) {
    final pathSuffix =
        ex.relativePath == null ? '' : ' (path: ${ex.relativePath})';
    final retrySuffix = ex.retryable ? ' You can retry this action.' : '';
    return 'iCloud ${ex.operation} failed: ${ex.message}'
        '$pathSuffix.$retrySuffix';
  }

  return ex?.toString() ?? 'Unknown error';
}

String formatProgressPercent(double? percent) {
  final safePercent = (percent ?? 0).clamp(0, 100).toDouble();
  return '${safePercent.toStringAsFixed(1)}%';
}
