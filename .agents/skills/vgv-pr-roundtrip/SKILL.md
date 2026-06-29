---
name: vgv-pr-roundtrip
description: >-
  Execute the exact VGV roundtrip ticket loop for a buildable plan slice: build
  the first or next appropriate slice, run the user-specified number of VGV
  review rounds before PR (default three), incorporate fixes as you go,
  commit/push, open a real PR, wait up to 30 minutes for PR reviews, use
  gh-address-comments, commit/push feedback fixes, reconcile docs and LEARNINGS,
  repeat until all feedback is accounted for, and stop only when the PR is
  mergeable with Greptile confidence 5/5.
---

# VGV PR Roundtrip

## Canonical Ticket Loop

Follow this checklist exactly unless the user overrides a number or step:

1. Complete the first or next most appropriate slice. Pay attention to
   `LEARNINGS.md`.
2. Complete the requested number of review rounds before PR. Default: exactly 3
   rounds. If the user says 4, run exactly 4. Track progress as `Review 1/3`,
   `Review 2/3`, `Review 3/3`, etc.
3. Incorporate changes as you go. Fix each review round before starting the
   next round.
4. Commit and push the completed local slice.
5. Open a real PR. Do not open a draft PR unless the user explicitly asks for a
   draft.
6. Wait up to 30 minutes for PR reviews/checks when the user requested the
   roundtrip workflow, then use the GitHub `gh-address-comments` skill (install
   the Cursor **github** plugin if it is not already enabled).
7. Commit and push PR feedback fixes.
8. Reconcile docs and update the correct `LEARNINGS.md`.
9. Round trip until all feedback is accounted for. Commit and push each
   feedback batch.
10. Stop only when the PR is mergeable and Greptile confidence is 5/5.

This is a completion loop, not a one-pass coding task.

## Linked Skills

Use these Wingspan skills at the named steps (invoke with `/build`, `/review`,
`/create-commit`, `/create-pr`, or load the matching skill by name):

| Step | Skill | Invocation |
| ---- | ----- | ---------- |
| 1 | build | `/build` |
| 2 | review | `/review` (repeat for each required round) |
| 4, 7, 9 | create-commit | `/create-commit` when commit discipline is needed |
| 5 | create-pr | `/create-pr` |
| 6+ | gh-address-comments | `/gh-address-comments` via **github** companion plugin |
| Pre-1 (not buildable) | plan, refine-approach, plan-technical-review | `/plan`, `/refine-approach`, `/plan-technical-review` |

### Companion plugin (required for step 6)

Install and enable the Cursor **github** plugin (e.g. `github@openai-curated`) so
`gh-address-comments` is available. This repo does not vendor GitHub plugin
content.

## Step 1 Gate: Find The Buildable Slice

Before building:

- Read the requested plan path, current branch, recent commits, and relevant
  `LEARNINGS.md`.
- If the requested file is an umbrella roadmap, do not build from it directly.
  Locate or create the next buildable part plan.
- If the roadmap still names a just-merged slice as next, reconcile docs first.
- State the selected slice and why it is the first or next most appropriate
  slice.
- Stay inside the plan's allowed package/file scope.

## Step 2 Gate: Review Count Is Hard

The review count is not advisory.

- Default to 3 `/review` rounds.
- Use the exact count when the user gives one, such as "four times" or "two
  minimum."
- After each round, list findings by category, fix them, validate, then start
  the next round.
- Do not open the PR before the required local review count is complete.
- Treat info-level findings as code-quality leads. If they are actionable,
  clean them up.
- If similar issues repeat, name the violated principle and fix the underlying
  contract/design rather than applying isolated patches.

## Step 6 Gate: GitHub Feedback Pass

After opening the PR:

- Wait up to 30 minutes for review bots/humans when running the full roundtrip.
- Poll PR checks and comments during that window.
- Use `/gh-address-comments` from the github companion plugin.
- Inspect review threads with thread-aware GitHub data, not flat comments only.
- Manually resolve GitHub review threads once fixed or truly non-actionable.
- For top-level bot comments without review-thread IDs, fix the issue or note
  that there is no thread to resolve.

## Step 10 Done Criteria

The loop is not done until all of these are true:

- all actionable local review findings are fixed or explicitly accounted for;
- all actionable PR feedback is fixed or explicitly accounted for;
- all resolvable GitHub review threads are resolved;
- required checks pass;
- branch is pushed;
- docs and `LEARNINGS.md` are reconciled;
- PR is mergeable;
- Greptile confidence is 5/5;
- Greptile says there are no files requiring special attention.

Do not merge by default. Stop at merge-ready unless the user explicitly asks to
merge. If asked to merge, merge only after the done criteria pass, then switch
to `main`, pull fast-forward, prune, delete only confirmed merged/stale
branches, and reconcile docs on `main` when needed.

## Non-Negotiables

- Do not treat local green tests as the end of this workflow.
- Do not skip or compress the requested number of review rounds.
- Do not hide skipped checks or unresolved feedback.
- Do not add broad try/catch blocks to silence failures. Handle typed
  recoverable failures at the correct boundary and let programming errors
  bubble.
- Do not write Flutter app code when the plan is bottom-layer, repository, or
  CLI-only.
- Do not trust stale review summaries. Re-read live PR head, checks, comments,
  and review threads after every push.
