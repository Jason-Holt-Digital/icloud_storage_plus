# NSMetadataQuery notes (iCloud)

This repo uses `NSMetadataQuery` in the native (iOS/macOS) layer for:

- Listing container contents (`gather`)
- Monitoring upload/download progress
- Getting iCloud-specific metadata for listed items

This note exists to prevent common misunderstandings when working with
`NSMetadataQuery`.

## What `NSMetadataQuery` is (and isn’t)

`NSMetadataQuery` queries the system’s ubiquitous metadata index. In practice
this means it can surface items that are known to iCloud even if they are not
fully downloaded yet. It is asynchronous and notification-driven.

`FileManager.fileExists(atPath:)` is a filesystem check. It does not “wait for”
metadata indexing or downloads.

## Query lifecycle gotchas

- Results are not immediately available after `query.start()`.
  - Wait for `NSMetadataQueryDidFinishGathering` for initial results.
  - When monitoring, handle `NSMetadataQueryDidUpdate` for changes.
- Always stop queries you no longer need (`query.stop()`) and remove observers.
  Leaving queries running can leak resources and keep delivering notifications.
- Prefer specific predicates for single-item queries; use `beginswith` only
  when listing a container subtree.
- Use the correct iCloud scopes for your use-case (this repo uses the data and
  documents scopes for app-owned content).

## How this plugin uses it

- `gather()` uses `NSMetadataQuery` to list files/directories and to emit
  updates when you opt into streaming.
- Upload/download progress streams are backed by a query and emit percent
  updates via an event channel.
- `documentExists()` and `getItemMetadata()` use the local filesystem and URL
  resource values by design. They do not force downloads.

If your app needs a “remote-aware” view of what exists in the container, build
that from `gather()` rather than `documentExists()`.

For background on why progress monitoring and existence checks are separated,
see [Download flow rationale](download_flow.md).
