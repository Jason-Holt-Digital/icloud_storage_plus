/// A thin bridge to CloudKit's `CKSyncEngine` for the private database.
///
/// This library is separate from the document storage API in
/// `icloud_storage.dart`; it uses CloudKit only and never touches the iCloud
/// Drive ubiquity container. Requires iOS 17 or macOS 14.
library;

export 'src/cloudkit_sync/cloudkit_asset_store.dart';
export 'src/cloudkit_sync/cloudkit_records.dart';
export 'src/cloudkit_sync/cloudkit_sync_engine.dart';
export 'src/cloudkit_sync/cloudkit_sync_events.dart';
export 'src/cloudkit_sync/cloudkit_sync_exception.dart';
