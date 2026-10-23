# Background

Historical notes explain how the plugin arrived at its current local-operation boundary. They are not an alternative specification: current source and `AGENTS.md` take precedence when an older plan describes removed behavior.

## Reading map

| Record | What it explains |
| --- | --- |
| [Migrations](migrations.md) | Removed readiness policy, explicit version APIs, and typed boundary changes |
| [Lore](../lore.md) | Dated repository history |
| `doc/notes/download_flow.md` | Why local document operations determine read outcomes |
| `doc/notes/nsmetadataquery.md` | Metadata-query lifetime and the distinction from filesystem existence |
| `docs/plan/2026-05-26-fix-remove-icloud-readiness-timeout-layer-plan.md` | Removal of readiness waits and timeout-driven lifecycle errors |
| `docs/brainstorm/2026-05-26-copy-coordination-main-thread-follow-up.md` | A historical copy-coordination follow-up, not a description of all current dispatch paths |
| `BENCHMARK.md` | Path-normalization and directory-loop optimization rationale, with an optional local micro-benchmark |

`ai_specs/` and `docs/superpowers/plans/` preserve earlier proposals and consolidation plans. Do not restore a deleted policy because a historical checklist says to implement it. Consult [Native files](../systems/native-files/index.md) for today's helper and queue structure.

## Current design boundary

The plugin owns arguments, local paths, container resolution, local file operations, and the Flutter boundary. Apple owns sync timing, materialization, metadata freshness, and document conflicts. Apps choose explicit conflict-version actions; ordinary writes do not select a winner or remove versions (`AGENTS.md`, `lib/icloud_storage.dart`).

Performance notes do not establish iCloud latency or end-to-end throughput guarantees. This wiki did not rerun the optional benchmark in `BENCHMARK.md`.
