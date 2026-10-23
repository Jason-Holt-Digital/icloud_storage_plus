# Distribution and automation

This repository distributes a Flutter plugin, not a hosted service. Package publication and repository automation live in GitHub Actions; app deployment remains the consuming application's responsibility (`pubspec.yaml`, `.github/workflows/publish.yml`).

## Package publication

`pubspec.yaml` and both native podspecs declare version `4.0.0`. CocoaPods and SwiftPM sources are bundled with the Flutter package; their entry points are covered in [Configuration](reference/configuration.md).

Release versioning is managed by Release Please (`.github/workflows/release-please.yml`). It runs on pushes to `main` and on manual dispatch, uses the `dart` release strategy for the root package, and opens a release pull request that bumps `pubspec.yaml` and `CHANGELOG.md` (`release-please-config.json`, `.release-please-manifest.json`; baseline `4.0.0`, bootstrap commit `01ac70d`). Tags are plain version numbers with no `v` prefix. The workflow requires an Actions secret named `RELEASE_PLEASE_TOKEN` with Contents, Pull requests, and Issues write access; a preflight step fails the run when the secret is absent, and the release action is pinned to a commit identified as v5.0.0. `.github/RELEASES.md` documents the token setup and warns that merging a release PR creates a real tag and release.

`.github/workflows/publish.yml` runs on version-like tags without a `v` prefix, including tags created when a Release Please PR merges. It delegates to the Dart reusable publishing workflow, grants read access to contents and write access to the OIDC token, and selects the `pub.dev` environment. The tag must match the package version. Per `.github/RELEASES.md`, the `pub.dev` environment requires human approval before publishing, and automated agents must not merge release PRs or approve that environment.

`.github/workflows/publish-approval-canary.yml` is a separate environment-approval check, triggered manually or by changes to itself. Its job only prints an approval message. Whether the `pub.dev` environment requires a human reviewer is repository configuration, not established by the YAML alone.

## Workflow inventory

| Workflow | Trigger | Behavior and boundary |
| --- | --- | --- |
| `.github/workflows/factory-review.yml` | PR lifecycle events, including head synchronization | Variable-gated native deep review and security review; verifies writer actors, current head/base, non-draft same-repository PR, and prior completed review |
| `.github/workflows/factory-mentions.yml` | New issue/review comments and submitted reviews containing a command | Variable-gated human-writer `@droid` handling; rollout accepts open same-repository PRs, not issue-to-PR implementation |
| `.github/workflows/factory-triage.yml` | Newly opened issues | Variable-gated classification with constrained tools; separate validated classification comment; no implementation or label assignment |
| `.github/workflows/droid-wiki-refresh.yml` | Pushes to `main` | Generate/upload wiki, then hand Markdown and metadata to a separate rolling-PR publisher |
| `.github/workflows/publish.yml` | Matching version tags | Publish package through Dart reusable workflow |
| `.github/workflows/release-please.yml` | Pushes to `main`, manual dispatch | Open/update release PRs and create plain-version tags; requires `RELEASE_PLEASE_TOKEN` |
| `.github/workflows/publish-approval-canary.yml` | Manual dispatch or changes to itself | Check the publication environment approval path |

The review and mention workflows pin the Factory action to a commit identified as v10 and disable saved checkout credentials. The legacy `.github/workflows/droid.yml` and `.github/workflows/droid-review.yml` workflows, which ran the action's unpinned `main` branch on every PR or `@droid` mention, were removed in `e219229`; the commit message explains that keeping both would produce two reviews per PR and two replies per mention once the opt-in replacements are enabled.

## Rollout controls

The new workflows check `JHD_FACTORY_REVIEW_ENABLED`, `JHD_FACTORY_MENTIONS_ENABLED`, and `JHD_FACTORY_TRIAGE_ENABLED` against the string `true`. The YAML does not prove the repository's current variable values. Factory credentials must be configured separately; never put their values in documentation.

Native review is advisory: its configuration does not block critical/high findings through the action's security settings. This is not evidence that repository branch-protection checks are absent or optional.

## Wiki refresh

The refresh workflow fetches full history and restores `droid-wiki/` from a rolling `factory/droid-wiki` branch if available. Generation has read-only GitHub contents permissions. A separate job receives the generated artifact and updates a pull request using a narrowly scoped token or the default token (`.github/workflows/droid-wiki-refresh.yml`).

The artifact and staged path list exclude video and screenshot directories but retain hidden `.wiki-meta.json`, allowing later incremental generation. Default-token-created PRs do not trigger further workflows, as the workflow comments note. A publish failure becomes a warning rather than invalidating generated documentation.

## Validation limits

The checked-in workflow set does not define a general Flutter analyze/test matrix or a Darwin native-test job. Local contributor checks still matter. This wiki generation did not publish a package, modify workflows, or verify external protection rules.

See [Tooling](how-to-contribute/tooling.md), [Testing](how-to-contribute/testing.md), and [Trust boundaries](security.md).
