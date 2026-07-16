# De-Slop and De-Smell Reference

Use this reference when cleaning AI-generated residue, reviewing suspicious code, or deciding whether a smell deserves a behavior-preserving refactor.

## Contents

1. De-slop definition
2. De-smell definition
3. Slop catalog
4. Smell catalog
5. Fix patterns
6. Stop conditions
7. Review phrases
8. Related de-prop cleanup
9. Related de-repeat cleanup

## 1. De-slop definition

De-slop removes accidental codegen residue: vague structure, fake flexibility, noisy wrappers, speculative options, useless comments, defensive theater, and generic glue that makes the code look engineered while making behavior harder to trust.

De-slop is not simplification by deletion. It must preserve real safety, real domain boundaries, and real failure handling.

## 2. De-smell definition

De-smell treats smells as signals. A smell points to possible maintenance cost, but a fix is only valid when it is in scope, behavior-preserving, and cheaper after the change.

Do not convert every smell into an abstraction. Some duplication is safer than a wrong shared abstraction.

## 3. Slop catalog

### Vague wrapper slop

Symptoms:
- functions named `handleThing`, `processData`, `manageItems`, `doStuff`
- wrappers that add no validation, naming, policy, or ownership
- helpers that only reverse argument order or call another helper

Preferred fix:
- inline the wrapper when it adds no meaning
- rename it when it represents a real domain operation
- move it to the layer that owns the operation

### Fake robustness slop

Symptoms:
- `try/catch` that only logs and continues with corrupt state
- fallback values that hide missing required data
- optional chaining across data that should be contractually present
- `as any`, broad casts, or empty catches used to silence type/system failures

Preferred fix:
- make invalid state explicit
- preserve critical failure behavior
- surface errors where data integrity matters
- avoid swallowing failures in persistence, sync, calendar, file, API, worker, or auth paths

### Generic configurability slop

Symptoms:
- many boolean flags controlling unrelated behavior
- config objects with one caller
- generic components with mode strings for unrelated domains
- speculative extension points without real use cases

Preferred fix:
- split by domain or lifecycle
- keep repeated code until duplication is proven
- extract only stable shared internals

### Comment slop

Symptoms:
- comments that restate the next line
- comments explaining what a function used to do
- vague comments such as `// handle edge cases`
- TODOs with no owner, date, or concrete next action

Preferred fix:
- delete obvious comments
- replace vague comments with clearer names or explicit invariants
- keep comments that document non-obvious constraints, engine boundaries, performance tradeoffs, or external protocol requirements

### Hook and memo slop

Symptoms:
- `useMemo` around cheap values with unstable dependencies
- `useCallback` used everywhere without referential need
- `memo` hiding component design problems
- selector factories created per render without need

Preferred fix:
- remove ineffective memoization only after checking referential behavior
- keep memoization around expensive transforms, stable child props, virtualization, large lists, and selector boundaries
- avoid changing Reselect input selector behavior casually

### AI overengineering slop

Symptoms:
- excessive helper layers for simple expressions
- new mini-frameworks inside feature files
- needless generic types and callbacks
- speculative adapter interfaces before there are multiple implementations

Preferred fix:
- collapse shallow layers
- keep the direct implementation when the domain is still evolving
- introduce interfaces only for real seams: persistence, external APIs, platform adapters, or test boundaries

## 4. Smell catalog

### Long function

Signal: a function is doing orchestration, transformation, validation, and side effects together.

Safe fixes:
- extract pure transforms
- extract guard clauses
- extract side-effect adapters behind existing gateways
- keep orchestration readable and explicit

Unsafe fixes:
- split into arbitrary helpers named by implementation step
- hide domain order inside callbacks
- change async sequencing

### Large file

Signal: multiple responsibilities or too many private helpers in one place.

Safe fixes:
- move stable pure helpers to a local sibling file
- move domain logic to a domain module
- keep public API unchanged

Unsafe fixes:
- create a broad `utils.ts`
- move code across layers to make file sizes symmetrical
- split files without reducing conceptual load

### Deep nesting

Signal: too many conditions mixed with work.

Safe fixes:
- use guard clauses
- name predicates
- separate permission/loading/empty/error states from core logic

Unsafe fixes:
- flatten by changing branch priority
- combine conditions that represent different states

### Duplicate logic

Signal: same transformation, validation, formatting, permission check, or selector repeated.

Safe fixes:
- extract a pure helper if the logic has the same domain meaning
- centralize validation rules
- centralize date/time and recurrence logic in existing utilities or engines

Unsafe fixes:
- merge code that shares syntax but not ownership
- hide different permissions behind a generic option bag

### Feature envy

Signal: a module reaches into another module's data shape repeatedly.

Safe fixes:
- move the behavior to the owning module
- expose a narrower query/helper from the owner

Unsafe fixes:
- import deeper internals
- duplicate the owner logic locally

### Primitive obsession

Signal: repeated strings, booleans, numeric codes, or loose objects encode domain states.

Safe fixes:
- use existing enums, discriminated unions, constants, schemas, or canonical types
- add typed wrappers only when repeated behavior depends on them

Unsafe fixes:
- create a type system for one local branch
- rename public values without migration

### Shotgun surgery

Signal: one behavior change requires edits across many unrelated files.

Safe fixes:
- identify the missing owner
- centralize the rule behind an existing boundary

Unsafe fixes:
- add another broad utility used everywhere
- mutate all callers without defining ownership

### Mixed layer

Signal: UI performs persistence, sync, API, calendar expansion, or domain validation directly.

Safe fixes:
- move writes to mutation gateways
- move derivation to selectors
- move calendar/recurrence to engine or worker
- pass IDs and commands rather than storage clients

Unsafe fixes:
- make UI code cleaner while preserving the layer violation

## 5. Fix patterns

### Guard clause cleanup

Before:

```ts
function getLabel(task?: Task) {
  if (task) {
    if (task.title) {
      return task.title;
    } else {
      return 'Untitled';
    }
  }
  return 'Untitled';
}
```

After:

```ts
function getLabel(task?: Task) {
  if (!task?.title) return 'Untitled';
  return task.title;
}
```

This is safe because branch priority and outputs are unchanged.

### Bad abstraction rollback

Before:

```ts
function processEntity(entity: Task | Project | Document, mode: 'task' | 'project' | 'document') {
  if (mode === 'task') return renderTask(entity as Task);
  if (mode === 'project') return renderProject(entity as Project);
  return renderDocument(entity as Document);
}
```

Better:

```ts
renderTask(task);
renderProject(project);
renderDocument(document);
```

The abstraction removes no complexity. It hides domain differences and adds casting risk.

### Stable pure helper extraction

Before:

```ts
const visibleTasks = tasks.filter(task => !task.archived && task.projectId === projectId);
const visibleSubtasks = subtasks.filter(task => !task.archived && task.projectId === projectId);
```

After:

```ts
const belongsToActiveProject = (projectId: string) => (item: { archived?: boolean; projectId: string }) =>
  !item.archived && item.projectId === projectId;

const visibleTasks = tasks.filter(belongsToActiveProject(projectId));
const visibleSubtasks = subtasks.filter(belongsToActiveProject(projectId));
```

This is safe only if `archived` and `projectId` have the same meaning for both entities.

## 6. Stop conditions

Stop and report instead of editing when:

- the change requires schema, migration, API, route, command, or public type changes
- tests are red for unrelated reasons and no safe baseline exists
- duplication may represent separate domain concepts
- the fix changes persistence, sync, recurrence, permissions, or worker behavior
- the refactor would create a mega-component or utility junk drawer
- the user asked for cleanup but the real problem is architecture ownership

## 7. Review phrases

Use direct notes like:

- “This is true duplication: same domain rule, same owner, same lifecycle.”
- “This only looks duplicated. The two branches represent different domain concepts.”
- “This abstraction is shallow; it moves complexity into the caller.”
- “This is slop, not safety; it hides invalid state.”
- “This is a high-risk refactor because it touches sync or persistence semantics.”
- “I am leaving this duplication because the shared abstraction would be less clear.”

## 8. Related de-prop cleanup

When slop or smells come from React/Redux props rather than general code structure, read `de-prop.md`. Prop-specific cleanup has extra constraints around component API compatibility, render behavior, context scope, DOM prop forwarding, accessibility props, class merging, and selector reference stability.

Typical overlap:

- magic booleans are both generic configurability slop and prop API slop
- manually pushed `isActive`/`isSelected` flags are derived-state smells
- prop drilling may indicate a missing scoped provider, selector boundary, or composition slot
- missing `...props` forwarding can block accessibility and standard DOM behavior
- overusing context to avoid props can create hidden dependencies and wide rerenders

## 9. Related de-repeat cleanup

Use `de-repeat.md` when the smell is mainly repeated decision paths rather than generic slop:

- growing if/else or switch chains
- repeated branch bodies
- repeated selector/date/permission/validation rules
- duplicated loops over the same data
- circular dependencies caused by misplaced shared helpers
- high cyclomatic complexity from nested branches

Do not de-repeat code just because it looks repetitive. Repetition may encode different side effects, ownership, or domain semantics.


## Related de-series references

Use the narrower references when the smell points to a specific owner:

- Repeated branches, cyclomatic complexity, or circular dependencies: `de-repeat.md`.
- Prop APIs, magic booleans, prop drilling, or context-vs-props: `de-prop.md`.
- Mirrored state or stored derived values: `de-state.md`.
- Effects used for derivation, fetching, action relay, or reset choreography: `de-effect.md`.
- Selector duplication, unstable selector outputs, or Reselect cache issues: `de-selector.md`.
- UI/domain/infrastructure boundary leaks: `de-layer.md`.
- Loose types, magic strings, or unsafe casts: `de-type.md`.
- Render churn, unstable references, or context storms: `de-render.md`.
