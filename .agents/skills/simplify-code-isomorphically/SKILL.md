---
name: simplify-code-isomorphically
description: Behavior-preserving simplification and refactoring; enforces the repo-root AGENTS.md when agents skip rules. Use for simplify, refactor, DRY, de-slop/de-smell/de-prop/de-repeat/de-state/de-effect/de-selector/de-layer/de-type/de-render, god files, or line-count cleanup. Pair vercel-composition-patterns and vercel-react-best-practices for React shape/perf; typescript-best-practices for types. Preserves APIs, selectors, persistence, sync, calendar/recurrence, a11y, and render behavior.
---

# Simplify Code Isomorphically

Refactor as a system guardian, not a line-count optimizer. Preserve observable behavior while reducing accidental complexity, slop, or proven duplication.

An isomorphic refactor keeps the same public contracts, inputs, outputs, side effects, async timing where observable, error behavior, rendered behavior, accessibility behavior, data ordering, state transitions, selector semantics, persistence writes, and sync behavior.

## Governance — read before step 1

| Layer | Role |
|-------|------|
| **`AGENTS.md` at the repo root** | Global contract for this project (always applies) |
| **This skill** | Refactor operator manual when simplifying/cleaning — **must be followed in full when this skill is invoked** |

**Why this skill repeats AGENTS.md rules:** agents often skip standalone rule files. Duplication here is **intentional enforcement**, not drift. On conflict, **AGENTS.md wins**; otherwise comply with **both**.

**Pair with (do not substitute):**

| Topic | Also read |
|-------|-----------|
| Boolean props, compound components, variant APIs | `vercel-composition-patterns` — overlaps **de-prop**; composition = target shape, this skill = behavior-safe cutover |
| React perf (waterfalls, bundle, rerenders) | `vercel-react-best-practices` + `react-performance-optimizer` when optimizing hot paths — behavior must stay stable |
| TypeScript contracts | `typescript-best-practices` — overlaps **de-type** |
| Effect removal | `no-useEffect` + `references/de-effect.md` |
| Redux / selectors | `redux-toolkit-react-redux-standards` — overlaps **de-selector** / **de-layer** |

**Hard limits (from AGENTS.md — repeated so they are not skipped):** flag and split when safe — functions **> 30 lines**, files **> 300 lines**, nesting **> 2**, modules with **> 5** public methods; do not auto-refactor on line count alone; still obey forbidden moves and risk tiers below.

## First Principles

Preserve structure before polishing style. Clean but structurally wrong is failure. Slightly messy but structurally correct is acceptable.

Prefer the smallest safe change. Duplication is allowed when abstraction would hide real domain differences or increase maintenance cost.

Do not refactor unrelated systems while here. Flag larger problems, but do not fix them without explicit instruction.

## Workflow

### 1. Classify the request

Identify the user mode before editing:

- **Simplify**: remove local noise while preserving shape.
- **Refactor**: improve internal structure without changing external behavior.
- **DRY or reuse**: unify only proven duplication.
- **De-slop**: remove AI/codegen residue, fake robustness, unnecessary wrappers, vague comments, and speculative code.
- **De-smell**: detect and address maintainability smells only when the fix is behavior-preserving and in scope.
- **De-prop**: clean React/Redux prop APIs, prop drilling, magic booleans, manual derived-state props, class merging, defaults, and primitive prop forwarding without changing behavior.
- **De-repeat**: reduce repeated branch logic, growing if/else or switch chains, duplicate loops, repeated selector/date/permission rules, circular dependency smells, and cyclomatic complexity without hiding domain differences.
- **De-state**: remove duplicated, mirrored, or manually synchronized state; derive from canonical values, selectors, URL/state machines, or owned local state instead.
- **De-effect**: remove unnecessary `useEffect`-style synchronization; replace effects with derivation, event handlers, query libraries, keys/remounts, or explicit external-sync hooks.
- **De-selector**: clean Redux/Reselect data paths, selector duplication, unstable selector outputs, cache-thrashing parameterized selectors, and component-local derived store logic.
- **De-layer**: restore architectural boundaries when UI, state, domain, infrastructure, persistence, sync, workers, or calendar engines leak into each other.
- **De-type**: tighten loose, stringly, or unsafe type contracts while preserving public behavior.
- **De-render**: reduce render churn, unstable references, over-broad context, unnecessary memoization, and excessive reactive surface area.
- **Architecture cleanup**: stop if the change crosses public API, schema, persistence, sync, permission, recurrence, or state-model boundaries; report that this needs architectural review.

Classify risk:

- **Low risk**: styling, isolated UI, pure helpers, local readability.
- **Medium risk**: state, selectors, data flow, view composition, shared components.
- **High risk**: data models, persistence, sync, calendar engine, recurrence, permissions, migrations, storage, auth, workers.

For high-risk areas, minimize edits and require a clear safety loop.

### 2. Map the behavior surface

Before changing code, identify what must stay stable:

- public exports, props, types, route names, action names, event names
- selector inputs, outputs, memoization assumptions, reference stability
- database queries, mutation gateways, API payloads, persistence writes
- async order, retry behavior, debouncing, throttling, queues, cancellation
- rendered DOM structure when CSS, tests, focus, keyboard, or accessibility depend on it
- loading, empty, error, optimistic, rollback, disabled, and permission states
- date/time, timezone, recurrence, all-day, drag-and-drop, and worker semantics

If behavior is unclear, ask for tests or restrict the change to mechanical edits.

### 3. Establish the safety loop

Identify how to know behavior stayed the same:

- typecheck
- unit tests
- integration tests
- story/snapshot/visual check
- repro script
- lint rule
- selector recomputation check
- profiler baseline
- manual smoke path

Never perform a risky refactor without a safety loop. If no safety loop exists, add characterization tests around public behavior or keep edits tiny and reversible.

### 4. Separate true duplication from coincidental similarity

Treat two pieces of code as true duplication only when they share:

- same domain meaning
- same lifecycle
- same data ownership
- same failure behavior
- same permission model
- same future direction
- same abstraction level

If two blocks merely look similar, keep them separate or extract only a small presentational/pure helper below the domain boundary.

### 5. Choose the correct refactor move

Use the first move that solves the real problem:

1. **Inline** misleading abstractions that only pass arguments through.
2. **Delete** code that is proven unused, unreachable, or duplicate under the safety loop.
3. **Rename** vague names only when the new name reflects real domain meaning.
4. **Extract** pure helpers for repeated transformation, validation, formatting, or guard logic.
5. **Move** logic to the layer that owns it.
6. **Unify** components only when interaction, data, state, and future behavior match.
7. **Stop** when a correct fix requires schema, public API, persistence, or architecture changes.

Use the deletion test before creating or keeping an abstraction: if this helper/component/module disappeared, would complexity vanish or reappear across callers? If it only moves complexity elsewhere, it is shallow.

### 6. Apply the de-series deliberately

Use a focused cleanup mode rather than trying to fix everything at once:

- **De-slop / de-smell**: remove residue and flag structural smells. Read `references/de-slop-and-de-smell.md`.
- **De-prop**: repair component API shape and prop ownership. Read `references/de-prop.md`. If the issue is boolean/mode prop sprawl or mega-components, also read **`vercel-composition-patterns`** (`architecture-avoid-boolean-props`, `architecture-compound-components`, `patterns-explicit-variants`) — refactor toward composition without changing behavior in one step.
- **De-repeat**: collapse repeated decision paths and reduce cyclomatic complexity. Read `references/de-repeat.md`.
- **De-state**: remove duplicate or mirrored state. Read `references/de-state.md`.
- **De-effect**: eliminate unnecessary effects and effect-as-control-flow. Read `references/de-effect.md`.
- **De-selector**: clean Redux/Reselect derivation paths. Read `references/de-selector.md`.
- **De-layer**: restore ownership boundaries. Read `references/de-layer.md`.
- **De-type**: tighten type contracts without API churn. Read `references/de-type.md`.
- **De-render**: reduce avoidable render churn. Read `references/de-render.md`.

A de-series label is a lens, not permission to over-refactor. If the requested cleanup uncovers a higher-risk architectural decision, stop and report.

### 7. Respect forbidden moves

Do not:

- introduce new state when it can be derived
- store derived values as source of truth
- duplicate date/time, selector, permission, validation, persistence, or sync logic
- use effects to derive state, relay user actions, or reset components when a key/remount or event handler is the owner
- mix UI rendering with domain logic
- access APIs or persistence directly from UI components
- bypass existing state, selector, engine, gateway, or sync layers
- introduce parallel patterns beside existing ones
- replace explicit props with broad context without proving ownership, scope, and render behavior
- collapse repeated branches when branch order, side effects, or failure behavior differ
- convert domain-specific branches into a generic strategy map without a shared contract
- pass derived visual flags when a canonical value can safely derive the state
- create abstractions for hypothetical future use
- merge domain concepts because their UI shapes overlap
- move calculations into Reselect input selectors
- return fresh arrays/objects from selectors unless reference churn is intended and safe
- change public names, exported types, schema, routes, payloads, or command contracts unless explicitly requested
- use any where unknown can be used, or omit explicit return types on public/exported APIs
- rely on union member ordering for determinism (stableTypeOrdering is always active in TS 7)
- use legacy config options like baseUrl, target: "es5", or moduleResolution: "node" for new configurations

### 8. Shared stack constraints (state management, databases, and local-first architectures)

When working in state-driven or local-first architectures:

- Keep the global state store (e.g., Redux, Zustand) as the hot read model for the UI.
- Keep durable storage, local databases, and network sync behind clear mutation gateways or controllers.
- Keep UI components from writing directly to databases (e.g., SQLite, Supabase), local storage, files, or external APIs; route through actions or gateway functions instead.
- Keep global state minimal and normalized.
- Keep derived data in selectors or computed properties.
- Keep cross-entity relationships as IDs, not nested copies.
- Keep views as projections, not data owners.
- Keep complex calculations, date calculations, scheduler, or background logic in separate workers or utility modules.
- Keep all date handling in shared utility files.
- Preserve boundaries between the data engine, state management, controllers, and UI presentation shells.
- Use context only for stable environment concerns (like theme, locale, or global service interfaces), not for high-frequency reactive state.
- Do not merge distinct domain models just because their visual UI layouts or components resemble each other.

### 9. Use bundled resources

Read `references/de-slop-and-de-smell.md` when the request says de-slop, de-smell, cleanup, smells, reduce AI slop, reduce tech debt, or when judging whether a suspicious pattern should be fixed.

Read `references/de-prop.md` when the request involves React props, Redux prop drilling, component APIs, boolean flags, variants, CVA, context vs props, className merging, defaults, `...props`, slots, selected/active/checked states, or UI primitive cleanup.

Read `references/de-repeat.md` when the request involves repeated branches, cyclomatic complexity, repeated if/else or switch chains, lookup tables, strategy patterns, cyclic redundancy, circular dependencies, duplicated loops, or repeated selector/date/permission/validation logic.

Read `references/de-state.md` when the request involves duplicate state, mirrored props, stored derived values, local/global state conflicts, stale UI, Redux state shape, entity normalization, or source-of-truth cleanup.

Read `references/de-effect.md` when the request involves React effects, no-useEffect cleanup, effect-driven state sync, fetch-in-effect, action relay flags, dependency arrays, mount-only external sync, or key/remount resets.

Read `references/de-selector.md` when the request involves Redux selectors, Reselect, derived data, selector reference stability, parameterized selectors, inline `useSelector` calculations, recomputation, or normalized reads.

Read `references/de-layer.md` when the request involves boundary violations, UI writing persistence, mutation gateways, domain logic location, infrastructure leakage, calendar/worker ownership, or cross-layer dependencies.

Read `references/de-type.md` when the request involves `any`, unsafe casts, stringly typed variants/statuses, duplicated unions, primitive obsession, discriminated unions, type guards, or type-safe component APIs.

Read `references/de-render.md` when the request involves React performance, rerenders, unstable props, context churn, memoization, callbacks, list item performance, provider values, or render-time expensive derivation.

Read `references/guidance-examples.md` when you need concrete examples of safe vs unsafe refactors, component extraction, selector cleanup, mutation gateway protection, de-series examples, or architecture stop conditions.

Run `scripts/smell_scan.py` only as an initial heuristic scan for files or folders. Treat its output as a triage aid, not an authority. Do not auto-fix solely because the script flags something.

## Output Contract

When returning a refactor, include:

- behavior preserved
- simplification made
- files and functions changed
- risk classification
- verification performed or missing
- assumptions made
- refactors intentionally skipped because they would be unsafe, architectural, or out of scope

If providing a patch, keep it focused. If the safest answer is not to refactor, say so and explain the smaller valid next step.
