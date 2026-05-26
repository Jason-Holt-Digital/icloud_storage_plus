# Local file access rationale

This note explains why iCloud Storage Plus treats local Foundation file
operations as the source of truth and uses metadata queries primarily for
listing and progress reporting.

## Source of truth: local file operations

iCloud Drive is a local ubiquity folder. Apple owns sync scheduling,
materialization, freshness, and conflicts. The plugin's job is to perform the
local operation the caller requested.

For in-place reads, the authoritative signal is the document read path
(`UIDocument` on iOS, `NSDocument` on macOS). These APIs coordinate local access
and provide the success/failure outcome for the read.

That means:

- A successful open/read means Apple made local bytes available to the app.
- A file-not-found error from open/read is a genuine “not found.”
- Other errors are surfaced as native errors.

## Metadata queries are progress-only

`NSMetadataQuery` is a live monitor. It reports changes in the metadata index,
not a final “exists” answer. For download progress we only read the percent
downloaded value when available. We do not infer existence or failure from
empty results.

Progress streams close when an explicit transfer completes or errors. Metadata
state is not used as a plugin-owned readiness gate for in-place reads.

Existence checks (`documentExists`) use direct filesystem URLs rather than
metadata queries. iCloud placeholders are local entries, so `fileExists` can
return true once the directory metadata syncs, even if the file is not fully
downloaded.

## In-place access

Coordinated in-place reads (`readInPlace`) do not pre-check file existence.
Instead, they:

- Attempt a coordinated document open/read.
- Let Apple's local file/document APIs determine whether bytes are available.

File-not-found and other failures surface as errors (not null). Text reads use
UTF-8 decoding; use `readInPlaceBytes` for binary formats.

## Error codes

We map Cocoa file-not-found errors to distinct codes:

- `E_FNF` for `NSFileNoSuchFileError`
- `E_FNF_READ` for `NSFileReadNoSuchFileError`
- `E_FNF_WRITE` for `NSFileWriteNoSuchFileError`

All other errors are reported as native errors.
