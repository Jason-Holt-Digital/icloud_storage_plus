# Development workflow

Use a small branch/edit/verify/review loop, keeping Dart contracts and paired native implementations aligned. `AGENTS.md` defines the scope and verification expectations.

## 1. Establish the baseline

Inspect the worktree before editing and preserve unrelated changes. Create a focused working branch from the intended base; the branch name below is an example, not a naming policy. Run these commands from the repository root:

```bash
git status --short
git switch -c fix/local-file-operation
```

Read `AGENTS.md`, then the [contributor entry point](index.md) and the relevant system page. Decide whether the task changes a local operation or tries to manage Apple's sync lifecycle. Stop for a missing public-contract or ownership decision, not for routine affected checks.

## 2. Set up the package you are editing

For Dart/plugin work, from the repository root:

```bash
flutter pub get
```

For example-app work, run dependency resolution independently from `example/`:

```bash
cd example
flutter pub get
```

The example depends on the parent package by path (`example/pubspec.yaml`). The root analyzer excludes that nested package (`analysis_options.yaml`), so root analysis does not replace example analysis. See [Tooling](tooling.md) for SDK and native packaging setup.

## 3. Edit the owning layer

- Keep public argument rules in `lib/icloud_storage.dart`, platform signatures in `lib/icloud_storage_platform_interface.dart`, and transport decoding in `lib/icloud_storage_method_channel.dart`. Approved interface changes require callers and custom implementations to update directly.
- For native features, inspect and update both `ios/` and `macos/`, including document and Foundation call sites. Similar source trees have platform-specific scheduling and presenter behavior; parity does not mean blindly copying one implementation over the other. Follow [Local I/O](../systems/native-files/local-io.md) and [Queries and presenter lifecycle](../systems/native-files/observation-lifecycle.md).
- When adding or moving native production files, update the explicit source lists in `ios/icloud_storage_plus/Package.swift`, `macos/icloud_storage_plus/Package.swift`, `ios/icloud_storage_plus.podspec`, and `macos/icloud_storage_plus.podspec`. Keep nested test-harness files out of production targets.
- Keep example UI changes under the example's ownership boundary. Do not use them to add plugin-level retries, freshness policy, or telemetry (`AGENTS.md`).

## 4. Run targeted checks, then the appropriate broader checks

For a facade change, a useful first command from the repository root is:

```bash
flutter test test/icloud_storage_test.dart
```

Choose channel/model tests or Darwin Foundation tests for their respective changes using [Testing](testing.md). Once affected code is ready, run the root package checks:

```bash
flutter analyze
flutter test
```

For example changes, analyze independently from `example/`:

```bash
flutter analyze
```

Add or run suitable widget/integration verification when the example behavior warrants it; no example test suite is checked in. Changed native behavior also needs targeted native tests and, where runtime evidence is needed, the configured example on a supported Apple target with debug/platform logs (`AGENTS.md`).

For docs-only modifications, verify statements against source, check relative links, and inspect the diff. Do not require Flutter or native test runs merely because Markdown changed. Report unrelated failures without expanding scope.

## 5. Prepare the PR

Review the full diff and status. Explain the problem, behavior change, platform coverage, tests, and verification limits. Update `README.md` and relevant API documentation when a public contract changes; add caller migration guidance rather than preserving an obsolete duplicate API (`AGENTS.md`).

`CHANGELOG.md` has an `Unreleased` section and declares semantic versioning. Use it for user-visible release notes as appropriate. A routine PR does not require publishing or changing versions.

## Publication context

`pubspec.yaml`, `ios/icloud_storage_plus.podspec`, and `macos/icloud_storage_plus.podspec` currently declare `4.0.0`; keep package/native version declarations aligned when preparing a release. Do not confuse the independent example version in `example/pubspec.yaml` with the plugin version.

Release Please manages version bumps, `CHANGELOG.md` entries, and release tags from conventional commit titles on `main` (`.github/workflows/release-please.yml`, `.github/RELEASES.md`). Use `fix:` or `feat:` titles, with `!` or a `BREAKING CHANGE:` footer for breaking changes, so releases classify correctly; `chore:` commits alone do not trigger a release. Merging a Release Please PR creates a real tag that starts publication, so do not merge one to test the automation.

`.github/workflows/publish.yml` handles version-like tags without a `v` prefix through the Dart reusable publishing workflow and the `pub.dev` environment, which requires human approval. Review [Distribution and automation](../deployment.md) before any release action. This workflow is not a reason to tag or publish an ordinary contribution, and its YAML does not establish external reviewer or branch-protection policy.
