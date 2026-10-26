# Features
Active contributors: Jason, vishalrao8, dean

## Purpose

Choose among four capabilities: [file access](file-access.md), [listing and metadata](listing-and-metadata.md), [document observation](document-observation.md), and [conflict-version exposure](conflict-versions.md). All operate against the app's local ubiquity container; Apple owns background synchronization, materialization, freshness, and conflicts. A successful local operation is not confirmation that another device received it (`lib/icloud_storage.dart`, `README.md`).

## API choice

| Need | API | Important boundary |
| --- | --- | --- |
| Check availability or locate the container | `icloudAvailable`, `getContainerPath` | Check availability before operations; configure the app's entitlements first |
| Copy a large file into or out of the container | `uploadFile`, `downloadFile` | Paths cross Flutter channels, not file bytes; copies do not create a continuing sync relationship |
| Read or write small text/binary content | `readInPlace`, `readInPlaceBytes`, `writeInPlace`, `writeInPlaceBytes` | Entire contents are held in memory and cross the channel |
| Manage local entries | `delete`, `move`, `rename`, `copy` | Files and directories are supported; existing-directory copy replacement is not |
| Turn iCloud on for local files | `moveIntoContainer` | A move, not a copy; works offline; the destination must not exist |
| Make a container folder | `createDirectory` | Creates missing parents too; succeeds when the folder already exists |
| Undo a move into iCloud | `moveOutOfContainer` | Removes the item from iCloud on every device; use `downloadFile` to keep it |
| Discover container metadata and refresh hints | `gather`, optional `onUpdate` | Metadata-index snapshots, including document promises; eventually consistent |
| List one directory after a local mutation | `listContents` | Direct children with local filesystem representations, including placeholders |
| Query a known path without downloading content | `documentExists`, `getItemMetadata` | Filesystem existence or typed URL-resource metadata, not remote discovery |
| Observe an existing file | `watchDocumentChanges` | Invalidation/state hints; synchronous listener and explicit cancellation |
| Inspect and preserve conflict versions | `enumerateUnresolvedConflictVersions`, `copyConflictVersion`, `markConflictResolved` | App chooses policy and backup destination; removal is explicit and off by default |

The facade defines these entry points in `lib/icloud_storage.dart`; `README.md` explains the large-file/small-file distinction and `Documents/` convention for Files app visibility. The four capability guides above group related workflows rather than reproducing the README's five API tiers.

## Integration and modification entry points

Start with [Getting started](../overview/getting-started.md) for signing and container configuration. The [example app](../apps/example.md) demonstrates several transfer, listing, and mutation workflows. For implementation changes, use the [Dart boundary](../systems/dart-boundary.md) and [native files](../systems/native-files/index.md) pages instead of treating these feature guides as a second architecture reference.

## Key source files

| Path | Role |
| --- | --- |
| `lib/icloud_storage.dart` | Public operations, path validation, model exports |
| `README.md` | API selection, setup, caller-facing examples |
| `test/icloud_storage_test.dart` | Facade delegation and validation checks |
| `test/icloud_storage_method_channel_test.dart` | Channel decoding, stream lifecycle, failure-routing checks |

Scoped footprint: 1 Dart source file, 2 shared Dart test files, and 1 README listed above; these are not exclusive feature ownership counts. `git log origin/main --` over those paths yields 5 distinct nonbot human author labels. This is a history/knowledge-concentration proxy, not a people count: aliases such as Jason/Jason Holt and dean/Dean Yuan may refer to the same person. Contributor names above are shortened labels, not a current-maintainer assignment.
