# De-Repeat Reference

Use this reference when repeated branch logic, repeated decision paths, growing if/else or switch chains, duplicate loops, circular dependencies, or repeated work are the main source of complexity.

## Contents

1. De-repeat definition
2. Complexity terms
3. Repeat smell catalog
4. Fix patterns
5. Strategy and lookup-table examples
6. Circular dependency handling
7. Stop conditions
8. Review phrases

## 1. De-repeat definition

De-repeat removes accidental repetition in decision paths while preserving behavior. It focuses on repeated logic inside branches, repeated condition checks, duplicated transformations, redundant loops, and growing conditional chains that should collapse into one clear call or data-driven lookup.

De-repeat is not blind DRY. Keep repeated code when the branches represent different domain rules, different failure behavior, different permissions, different sync semantics, or different future direction.

## 2. Complexity terms

### Cyclomatic complexity

Cyclomatic complexity measures how many independent paths exist through code. High complexity usually appears as many `if`, `else if`, `switch`, `case`, loop, catch, ternary, `&&`, or `||` decisions.

Problem:

- too many nested conditions
- too many branch-specific paths to test
- repeated work inside each path
- branch order becomes a hidden contract
- small changes require editing many branches

Preferred fix:

- guard clauses for invalid or terminal paths
- lookup tables for direct value mapping
- strategy maps for behavior mapping
- normalization before branching
- one shared call after branch-specific values are selected

### Cyclic redundancy

Cyclic redundancy, in this cleanup context, means multiple parts of a program repeatedly do the same work or re-check the same rule. It creates a maintenance loop: fix one copy, hunt for the next copy, repeat.

Preferred fix:

- extract the repeated rule to the owner layer
- derive once and pass the canonical result
- centralize validation, permissions, formatting, or transformation in the existing shared utility or selector

### Circular dependencies

Circular dependencies occur when module A imports module B while module B imports module A. They often appear after repeated logic gets copied between modules or after shared helpers are placed in the wrong owner.

Preferred fix:

- move neutral shared code to a lower-level utility/module
- move domain-specific code to the owning domain module
- invert the dependency through a small interface when necessary
- split types/constants from runtime implementations if the cycle is type-only

Do not fix circular dependencies by creating a junk-drawer `utils` file. The new location must have clear ownership.

## 3. Repeat smell catalog

### Repeated branch bodies

Symptoms:

```ts
if (state === 'draft') {
  return buildCard(item, 'muted');
}
if (state === 'archived') {
  return buildCard(item, 'muted');
}
if (state === 'active') {
  return buildCard(item, 'strong');
}
```

Preferred fix:

```ts
const toneByState = {
  draft: 'muted',
  archived: 'muted',
  active: 'strong',
} as const;

return buildCard(item, toneByState[state]);
```

Use this only if branch order and missing-state behavior are preserved.

### Growing if/else lookup chain

Symptoms:

```py
def get_price(item):
    if item == "apple":
        return 1.0
    elif item == "banana":
        return 0.5
    elif item == "cherry":
        return 2.0
    return 0.0
```

Preferred fix:

```py
PRICES = {
    "apple": 1.0,
    "banana": 0.5,
    "cherry": 2.0,
}

def get_price(item):
    return PRICES.get(item, 0.0)
```

This is safe when each branch is a pure mapping from one key to one value.

### Repeated condition prefixes

Symptoms:

```ts
if (task.status === 'active' && task.assigneeId === userId) { ... }
if (task.status === 'active' && task.dueAt) { ... }
if (task.status === 'active' && task.priority === 'high') { ... }
```

Preferred fix:

```ts
if (task.status !== 'active') return null;

if (task.assigneeId === userId) { ... }
if (task.dueAt) { ... }
if (task.priority === 'high') { ... }
```

Guard the shared invariant once, then handle the independent cases.

### Repeated loops over the same collection

Symptoms:

```ts
const overdue = tasks.filter(isOverdue);
const blocked = tasks.filter(isBlocked);
const mine = tasks.filter(task => task.assigneeId === userId);
```

Possible fix:

```ts
const buckets = groupTaskFlags(tasks, userId);
```

Only do this if it truly reduces work and cognitive load. Three readable filters may be better than a clever reducer unless performance or consistency is a real problem.

### Repeated selector logic

Symptoms:

```ts
const activeTasks = Object.values(state.tasks.entities).filter(t => t.status === 'active');
const activeTaskIds = Object.values(state.tasks.entities).filter(t => t.status === 'active').map(t => t.id);
```

Preferred fix:

- keep input selectors simple
- put repeated calculation in a shared selector result function
- derive variants from the canonical selector if reference behavior remains acceptable

Do not move expensive work into Reselect input selectors.

## 4. Fix patterns

### Guard clauses

Use when nested branches are mostly validation, early exits, or terminal states.

Before:

```ts
function getLabel(task?: Task) {
  if (task) {
    if (!task.archived) {
      if (task.title) {
        return task.title;
      }
    }
  }
  return 'Untitled';
}
```

After:

```ts
function getLabel(task?: Task) {
  if (!task || task.archived || !task.title) return 'Untitled';
  return task.title;
}
```

### Lookup tables

Use when branches map a key to a static value.

Good targets:

- status to label
- status to icon
- status to tone
- product type to display metadata
- route kind to component metadata

Avoid when each branch has different side effects, authorization, retries, sync semantics, or logging.

### Strategy maps

Use when branches map a key to a behavior function.

```ts
const handlers = {
  task: handleTask,
  project: handleProject,
  document: handleDocument,
} satisfies Record<EntityKind, (entity: Entity) => Result>;

return handlers[kind](entity);
```

Use this only when all handlers share the same contract and error behavior. If each branch has different ownership or persistence semantics, keep explicit branching.

### Normalize once, call once

Use when branches differ only in how they prepare arguments.

```ts
const targetDate = isAllDay ? toAllDayDate(input) : toTimedDate(input);
return moveTaskTimePersisted({ taskId, targetDate });
```

Do not hide materially different commands behind one call.

### Data-driven JSX

Use when UI repeats the same component shape with different labels/icons/values.

```tsx
const statusOptions = [
  { value: 'online', label: 'Online', icon: Circle },
  { value: 'busy', label: 'Busy', icon: MinusCircle },
] as const;

return statusOptions.map(option => (
  <StatusItem key={option.value} option={option} currentValue={presence} />
));
```

Keep actions separate if permissions, disabled states, analytics, or mutation paths differ per option.

## 5. Strategy and lookup-table examples

### Python mapping

```py
PRICES = {"apple": 1.0, "banana": 0.5, "cherry": 2.0}

def get_price(item):
    return PRICES.get(item, 0.0)
```

### TypeScript status metadata

```ts
const TASK_STATUS_META = {
  active: { label: 'Active', tone: 'green' },
  review: { label: 'In review', tone: 'amber' },
  completed: { label: 'Completed', tone: 'neutral' },
} as const satisfies Record<TaskStatus, { label: string; tone: Tone }>;

export function getTaskStatusMeta(status: TaskStatus) {
  return TASK_STATUS_META[status];
}
```

This reduces repeated status display logic while keeping canonical enum ownership visible.

### React branch collapse

Before:

```tsx
if (view === 'table') return <ViewButton icon={Table} label="Table" active />;
if (view === 'kanban') return <ViewButton icon={Kanban} label="Kanban" active />;
if (view === 'calendar') return <ViewButton icon={Calendar} label="Calendar" active />;
```

After:

```tsx
const VIEW_META = {
  table: { icon: Table, label: 'Table' },
  kanban: { icon: Kanban, label: 'Kanban' },
  calendar: { icon: Calendar, label: 'Calendar' },
} as const;

const meta = VIEW_META[view];
return <ViewButton icon={meta.icon} label={meta.label} active />;
```

This is safe when the rendered behavior is otherwise identical.

## 6. Circular dependency handling

When a de-repeat cleanup reveals a circular dependency, do not patch the import randomly. Identify ownership:

- If both modules need constants or types, move constants/types to a lower-level `*.types`, `*.constants`, or domain schema module.
- If UI imports domain and domain imports UI, move UI-specific logic out of domain.
- If two domains need each other, extract the shared relationship rule into the relationship/domain service layer.
- If only tests create the cycle, fix test helpers rather than production ownership.

Bad fix:

```ts
// common/utils.ts becomes a dumping ground for task, project, document, and calendar logic.
```

Good fix:

```ts
// task-status-meta.ts owns task status presentation metadata.
// task-selectors.ts imports it if selector output explicitly includes display metadata.
// UI imports it only when UI owns presentation.
```

The file name should explain ownership. A generic name like `helpers.ts`, `utils.ts`, or `common.ts` requires extra scrutiny.

## 7. Stop conditions

Stop and report instead of refactoring when:

- repeated branches have different side effects
- branch order is semantically important and not covered by tests
- a lookup table would hide permissions or failure behavior
- one branch writes through a persisted mutation gateway and another updates local draft state
- one branch handles recurrence/timezone/all-day behavior
- repeated logic belongs to different domains with different future direction
- the fix requires schema, API, route, command, storage, sync, or public prop changes
- a circular dependency points to an unresolved ownership problem

## 8. Review phrases

Use precise language:

- “This is a lookup-table candidate because every branch maps one key to one pure value.”
- “This is not safe to de-repeat because the branches share shape but not failure behavior.”
- “Cyclomatic complexity is high here, but the safe first move is guard clauses, not a strategy abstraction.”
- “This circular dependency is an ownership smell. I would extract the neutral type/constants layer, not create a generic utils file.”
- “The repeated selector logic should move into a selector result function, not an input selector.”
