# Releases

This repository uses Release Please to manage the package version, changelog, and release tags.

## What it manages

- One root component that uses the `dart` strategy.
- The baseline version is 4.0.0.
- Tags are plain version numbers with no prefix, such as `4.0.1`.
- Release Please updates `pubspec.yaml`, `CHANGELOG.md`, and the manifest.

## Set up the token

The workflow needs an Actions secret named `RELEASE_PLEASE_TOKEN`. Without it, the workflow fails before the release action. It does not fall back to `GITHUB_TOKEN`, and it does not use Factory, Droid, an API key, or any AI service.

1. Create a fine-grained personal access token.
2. Set the resource owner to `Jason-Holt-Digital`.
3. Choose selected repository access, then select this repository.
4. Give it read and write access to Contents, Pull requests, and Issues.
5. If the organization requires approval for new tokens, get the token approved.
6. Save it as a repository Actions secret. You can also use an organization Actions secret that grants access to this repository.

Never print the token in logs or output. The workflow `permissions` block does not change what the token can do. Only the token's own permissions control that.

The credential preflight check only proves two things: the secret exists, and the token can read the repository. It does not prove the token can write.

## Run the workflow

- Push to `main`, or
- Open Actions, select Release Please, click Run workflow, and choose branch `main`.

## Write commits that trigger a release

- `fix:` and `feat:` commits trigger a release.
- To mark a breaking change, add `!` after the type or add a `BREAKING CHANGE:` footer.
- When you squash merge, use this same format in the squash title.
- `chore:` commits do not trigger a release on their own.

## First run

The first run may not open a release PR. When a release PR does open, compare its diff and changelog with the 4.0.0 baseline and with earlier tags. If an earlier tag matches, Release Please can scan from that tag instead of `bootstrap-sha`, so older commits may still show up in the notes.

## Verify a release

A green run with nothing to release does not fully prove the setup works. To prove it:

1. Merge a real `fix:` or `feat:` change into `main`.
2. Check that Release Please opens a release PR and that its checks pass.

> [!IMPORTANT]
> After you merge the release PR, Release Please creates a tag. That tag can start the existing [publish workflow](workflows/publish.yml), which publishes the package to pub.dev for real through OIDC. The `pub.dev` environment requires human approval before the publishing job can run. Automatic agents must not merge release PRs or approve that environment. Before you merge, check the publishing setup and make sure the package is ready to release. Never merge the release PR just to test.

3. Merge the release PR only when you want to publish the release.
4. Check the GitHub release and tag, then check the publish workflow run.

Do not make dummy changes or dummy releases to test the setup.

## Files

- [Workflow](workflows/release-please.yml)
- [Release Please config](../release-please-config.json)
- [Release manifest](../.release-please-manifest.json)
