# Tooling

The development toolchain is Flutter/Dart plus Apple-native packaging and Foundation XCTest harnesses. Repository automation is separate from the plugin runtime (`pubspec.yaml`, `AGENTS.md`).

## Flutter package setup

Put a compatible Flutter SDK on `PATH` and inspect the environment before choosing checks. From the repository root:

```bash
flutter --version
flutter doctor -v
flutter pub get
```

`pubspec.yaml` declares Dart `>=3.0.0 <4.0.0`, Flutter `>=3.10.0`, and `very_good_analysis` as a development dependency. `example/pubspec.yaml` has a separate Dart constraint and dependencies. Declared lower bounds are not proof of one fully resolved development toolchain; no root or example dependency lockfile is checked in. See [Dependencies](../reference/dependencies.md).

`README.md` documents optional Flutter Swift Package Manager integration for Flutter 3.24 or later. Enable it intentionally in the consuming development environment if that is the packaging path being tested:

```bash
flutter config --enable-swift-package-manager
```

This changes Flutter configuration; it is not required merely to edit documentation. Native runtime work needs an Apple target/toolchain, signing, and container setup described in [Getting started](../overview/getting-started.md).

## Analyzer contexts

| Configuration | Scope |
| --- | --- |
| `analysis_options.yaml` | Includes `package:very_good_analysis/analysis_options.yaml`; excludes `example/**` and `pigeons/**`. The exclusion does not establish an active Pigeon generation pipeline. |
| `example/analysis_options.yaml` | Includes `package:flutter_lints/flutter.yaml` for the independently resolved example package. |

For root package code, run from the repository root:

```bash
flutter analyze
flutter test
```

For example changes, run separately from `example/`:

```bash
flutter pub get
flutter analyze
```

The example's path dependency points to the parent plugin (`example/pubspec.yaml`). Root analysis does not validate the excluded nested app. There are no checked-in example widget/integration tests to run as an existing suite; see [Testing](testing.md) for appropriate additions or runtime verification.

No configured generated-code system is evident in `pubspec.yaml`, `example/pubspec.yaml`, or the checked-in implementation layout. Do not add a speculative `build_runner`/Pigeon step or regenerate native scaffolding for ordinary edits. `AGENTS.md` requires generation only when changed generated inputs actually need it.

## Production packaging versus native test harnesses

| Entry points | Purpose |
| --- | --- |
| `ios/icloud_storage_plus/Package.swift`, `macos/icloud_storage_plus/Package.swift` | Production SwiftPM targets: explicit document/router/Foundation source lists and privacy resources. They exclude the nested harness manifest, tests, and placeholder. |
| `ios/icloud_storage_plus.podspec`, `macos/icloud_storage_plus.podspec` | CocoaPods production source/resource lists and Flutter/FlutterMacOS dependencies. |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Package.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Package.swift` | Standalone Foundation helper library/XCTest targets for supported Darwin testing, not a second shipping plugin API. |

Production and harness manifests use Swift tools 5.9; the podspecs declare Swift 5.0. Native deployment floors are iOS 13.0 and macOS 10.15. Do not infer that a Linux Swift installation can exercise the Apple APIs or that a plain top-level `swift build` validates Flutter integration.

When native source membership changes, review both production SwiftPM manifests and both podspecs as well as the paired helper/test trees. [Configuration](../reference/configuration.md) explains consumer setup; [Testing](testing.md) provides the nested `swift test --package-path` commands.

## Optional agent guidance

`.agents/skills/simplify-code-isomorphically/SKILL.md` supplies behavior-preserving refactoring guidance and references under `.agents/skills/simplify-code-isomorphically/`. It is contributor tooling, not plugin runtime code or a required build step. The skill explicitly gives `AGENTS.md` precedence; generic skill examples do not expand this plugin's ownership boundary.

## Bootstrap script warning

Inspect `scripts/jules_setup.sh` before considering it. It is a Linux environment bootstrap, not a harmless package-local setup command:

- Uses `sudo apt-get` to update/install system dependencies.
- Clones Flutter's `stable` branch into `$HOME/flutter` when absent and downloads Flutter artifacts.
- Alters the process `PATH` and persists a Flutter path entry in `$HOME/.bashrc`.
- Runs `flutter doctor -v`.
- Ends with `git checkout .`, which can discard tracked working-tree edits in its execution scope, not merely reset the script's executable bit.

Do **not** run it on a dirty worktree or use it as routine cleanup. Its sudo, network, SDK, shell-profile, and destructive Git effects need deliberate review; ordinary contributors can use an already configured SDK and the package-scoped commands above. The script is not needed for docs-only validation.

## Repository workflows

Publication, advisory review/mention/triage automation, and wiki refresh live under `.github/workflows/`. Read [Distribution and automation](../deployment.md) for exact triggers, permissions, rollout variables, and publication context rather than duplicating or inferring required checks here.

Those workflow files do not establish a general Flutter/native test matrix or external branch-protection settings. Contributors still choose the affected checks in `AGENTS.md` and report unavailable Apple runtime verification explicitly.
