# Refactor Guidance Examples

Use these examples as patterns for deciding what to change, what to preserve, and when to stop.

## Contents

1. Safe component extraction
2. Unsafe mega-component extraction
3. Selector cleanup
4. Mutation gateway protection
5. Calendar and recurrence stop condition
6. De-slop example
7. De-prop examples
8. Final response examples

## 1. Safe component extraction

Request: “These two cards repeat the same avatar/title/date block. Can we simplify?”

Safe move:

```tsx
function CardHeaderMeta({ avatarUrl, title, dateLabel }: Props) {
  return (
    <div className="card-header-meta">
      <Avatar src={avatarUrl} />
      <div>
        <strong>{title}</strong>
        <span>{dateLabel}</span>
      </div>
    </div>
  );
}
```

Use this when the extracted piece is presentational, has no domain-specific ownership, and does not change event, permission, focus, loading, or state behavior.

Report:

“Extracted only the repeated presentational header. Left task/project-specific actions separate because their permissions and lifecycle differ.”

## 2. Unsafe mega-component extraction

Bad move:

```tsx
<EntityCard
  entity={entity}
  type="task"
  showProjectControls
  enableRecurrence
  allowInlineStatus
  useDocumentPreview={false}
/>
```

Why unsafe:

- flags encode unrelated modes
- entity ownership is unclear
- future changes risk cross-domain regressions
- callers must understand hidden branch combinations

Better move:

- keep `TaskCard`, `ProjectCard`, and `DocumentCard`
- extract `CardShell`, `CardHeaderMeta`, or `StatusPill` only if those are truly shared

## 3. Selector cleanup

Unsafe selector:

```ts
const selectVisibleTasks = createSelector(
  [(state: RootState) => expensiveNormalize(state.tasks.entities)],
  normalized => normalized.filter(task => !task.archived)
);
```

Safer selector:

```ts
const selectTaskEntities = (state: RootState) => state.tasks.entities;

const selectVisibleTasks = createSelector(
  [selectTaskEntities],
  entities => Object.values(entities).filter(task => !task.archived)
);
```

Keep input selectors simple. Put calculation in the result function so memoization can do its job. Do not change selector result reference stability unless the task explicitly includes performance architecture.

## 4. Mutation gateway protection

Unsafe UI cleanup:

```tsx
function TaskDateButton({ taskId, date }) {
  return <button onClick={() => db.execute('UPDATE tasks SET start = ? WHERE id = ?', [date, taskId])}>Move</button>;
}
```

Safer boundary:

```tsx
function TaskDateButton({ taskId, date }) {
  const dispatch = useAppDispatch();
  return <button onClick={() => dispatch(moveTaskTimePersisted({ taskId, date }))}>Move</button>;
}
```

The refactor should preserve the mutation gateway. UI dispatches intent; domain/persistence layers own validation, optimistic update, database write, rollback, and error handling.

## 5. Calendar and recurrence stop condition

Unsafe cleanup:

```ts
const visibleOccurrences = events.flatMap(event => expandRRule(event.rrule, monthStart, monthEnd));
```

Why unsafe:

- recurrence expansion belongs in the calendar engine or worker
- timezone, all-day projection, exceptions, and instance overrides are high-risk
- moving this into UI may look simpler but damages ownership

Correct response:

“Not refactoring this into the component. The simplification would violate the calendar engine boundary. The safe change is to add a clearer engine selector/API or rename the worker result, not duplicate expansion in UI.”

## 6. De-slop example

Before:

```ts
// This function handles the item and returns the processed result
export function handleItemProcessing(data: any, options?: { fallback?: boolean }) {
  try {
    if (data && data.name) {
      return data.name;
    }
    if (options?.fallback) {
      return 'Untitled';
    }
    return 'Untitled';
  } catch (e) {
    console.log(e);
    return 'Untitled';
  }
}
```

After, if the behavior is truly just label fallback:

```ts
export function getItemLabel(item: { name?: string } | null | undefined) {
  return item?.name || 'Untitled';
}
```

Why this is safe:

- same output for the observed behavior
- useless option removed because both branches returned the same fallback
- comment removed because the function name now carries meaning
- broad catch removed because property access on this input shape is not a real failure boundary

Do not apply this pattern to storage, sync, API, file, calendar, worker, or auth code without a safety loop.

## 7. De-prop examples

### Magic booleans to semantic variants

Before:

```tsx
<Button isPrimary isGhost />
```

After:

```tsx
<Button intent="ghost" />
```

This is safe when the booleans were mutually exclusive visual modes and the new enum preserves the same chosen mode. It is unsafe if callers relied on hidden precedence between conflicting booleans and there is no test or migration path.

### Derived state instead of manual visual flags

Before:

```tsx
<StatusOption label="Online" isActive={presence === 'online'} />
```

After:

```tsx
<StatusOption value="online" currentValue={presence} />
```

The component derives `isActive` internally from canonical state. Do this when the comparison is repeated across callers and the component owns the option semantics.

## 8. De-repeat examples

### Lookup table for pure value mapping

Before:

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

After:

```py
PRICES = {"apple": 1.0, "banana": 0.5, "cherry": 2.0}

def get_price(item):
    return PRICES.get(item, 0.0)
```

This is safe because every branch maps one input key to one pure value and the default behavior is preserved.

### Strategy map for shared handler contracts

Before:

```ts
if (kind === 'task') return handleTask(entity);
if (kind === 'project') return handleProject(entity);
if (kind === 'document') return handleDocument(entity);
```

After:

```ts
const handlers = {
  task: handleTask,
  project: handleProject,
  document: handleDocument,
} satisfies Record<EntityKind, (entity: Entity) => Result>;

return handlers[kind](entity);
```

This is safe only when every handler has the same contract, error behavior, and ownership level. It is unsafe if one branch writes to persistence, one updates local draft state, and one triggers a calendar worker.

### Guard clause for repeated condition prefixes

Before:

```ts
if (task.status === 'active' && task.assigneeId === userId) showMine();
if (task.status === 'active' && task.dueAt) showDueDate();
if (task.status === 'active' && task.priority === 'high') showPriority();
```

After:

```ts
if (task.status !== 'active') return;

if (task.assigneeId === userId) showMine();
if (task.dueAt) showDueDate();
if (task.priority === 'high') showPriority();
```

This reduces repeated decision paths without hiding independent cases.

### Circular dependency cleanup

Unsafe fix:

```ts
// common/utils.ts now contains task status, project status, document labels, and calendar helpers.
```

Safer move:

- identify which layer owns the shared rule
- extract neutral types/constants to a lower-level module
- keep domain-specific behavior in the domain module
- avoid turning `utils` into a second architecture

Report:

“This circular dependency is not just an import problem. It is an ownership smell. I extracted only neutral constants/types and left domain behavior in the owning modules.”

## 9. Final response examples

### Good concise final report

Behavior preserved: same task labels, empty fallback, and props.

Simplification made: removed one shallow wrapper, extracted one pure `getTaskLabel` helper, and collapsed repeated guard clauses.

Risk: low. The change is local and pure.

Verification: typecheck passed. Existing label tests passed.

Skipped: did not merge `TaskCard` and `ProjectCard`; their action menus use different permission semantics.

### Good de-repeat report

Behavior preserved: same item-to-price mapping and same unknown-item fallback.

Simplification made: replaced a growing if/elif chain with a lookup table. This lowers cyclomatic complexity without changing the public function contract.

Risk: low. The change is a pure value mapping.

Verification: existing price tests passed; added one characterization test for the unknown-item fallback.

Skipped: did not convert nearby order-processing branches into a strategy map because those branches have different side effects and error behavior.

### Good refusal report

I would not refactor this as requested. The duplicated branches look similar, but one writes through the persisted mutation gateway and the other updates local draft state. Combining them would hide different consistency semantics behind a boolean flag.

Safe next step: extract only the shared date formatting helper and leave the write paths separate.


---

## De-state example: remove mirrored state

Bad:

```tsx
const [isActive, setIsActive] = useState(status === "active");

useEffect(() => {
  setIsActive(status === "active");
}, [status]);
```

Good:

```tsx
const isActive = status === "active";
```

Preserved behavior: the visual active state still follows the canonical `status`. Simplification: removed stale mirror state and one extra render cycle.

## De-effect example: event handler instead of relay flag

Bad:

```tsx
const [shouldArchive, setShouldArchive] = useState(false);

useEffect(() => {
  if (!shouldArchive) return;
  archiveTask(taskId);
  setShouldArchive(false);
}, [shouldArchive, taskId]);
```

Good:

```tsx
const handleArchive = () => archiveTask(taskId);
```

Preserved behavior: clicking still archives. Simplification: removed effect-as-control-flow.

## De-selector example: move repeated derived reads to owner selector

Bad:

```tsx
const overdue = useAppSelector(state =>
  state.tasks.ids
    .map(id => state.tasks.entities[id])
    .filter(task => task && task.dueAt && task.dueAt < todayKey)
);
```

Good:

```tsx
const overdue = useAppSelector(state => selectOverdueTasks(state, todayKey));
```

Preserved behavior: same task set and ordering. Risk: selector memoization and date-key semantics must be verified.

## De-layer example: UI emits intent, command owns write

Bad:

```tsx
async function handleComplete() {
  dispatch(taskCompleted({ id: task.id }));
  await db.execute("UPDATE tasks SET completed = 1 WHERE id = ?", [task.id]);
}
```

Good:

```tsx
const completeTask = useCompleteTaskCommand();
const handleComplete = () => completeTask({ taskId: task.id });
```

Preserved behavior: completion still happens. Simplification: UI no longer owns persistence ordering, rollback, or sync failure semantics.

## De-type example: semantic union instead of string prop

Bad:

```ts
type BadgeProps = { tone?: string };
```

Good:

```ts
type BadgeTone = "neutral" | "success" | "warning" | "danger";
type BadgeProps = { tone?: BadgeTone };
```

Preserved behavior: same accepted internal values. Risk: exported public APIs may require a migration if callers pass arbitrary strings.

## De-render example: stabilize context provider value

Bad:

```tsx
<WorkspaceContext.Provider value={{ workspaceId, density, commands }}>
  {children}
</WorkspaceContext.Provider>
```

Good:

```tsx
const contextValue = useMemo(
  () => ({ workspaceId, density, commands }),
  [workspaceId, density, commands]
);

<WorkspaceContext.Provider value={contextValue}>
  {children}
</WorkspaceContext.Provider>
```

Preserved behavior: consumers receive the same values. Simplification: avoids avoidable consumer rerenders when parent rerenders for unrelated reasons.
