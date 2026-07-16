# De-effect Reference

Use de-effect when React code contains unnecessary effects, effect-driven state synchronization, action relay flags, fetch-in-effect, dependency-array choreography, or mount/reset logic that can be expressed more directly.

This reference complements a stricter no-useEffect skill. If that skill exists, use it for direct React effect replacement rules; use this reference inside refactors to decide whether an effect is structural slop or a legitimate external synchronization boundary.

## Goal

Effects are for synchronizing with external systems. They are not for deriving render state, relaying user actions, fixing prop changes, or manually coordinating component lifecycles.

## Common effect smells

- `useEffect` sets state from props/state.
- An effect responds to a boolean flag set by an event handler.
- An effect fetches data and manually manages cache/stale/cancellation logic.
- An effect resets state when an ID prop changes.
- An effect exists only to keep two local states in sync.
- Dependency arrays contain unstable objects/functions and get patched with lint disables.
- Effects run on every render due to newly created dependencies.
- Effects write to Redux or persistence from a component.

## Replacement patterns

### 1. Derive state during render

Bad:

```tsx
const [filtered, setFiltered] = useState<Task[]>([]);

useEffect(() => {
  setFiltered(tasks.filter(task => task.status === status));
}, [tasks, status]);
```

Good:

```tsx
const filtered = tasks.filter(task => task.status === status);
```

If the calculation is expensive and local:

```tsx
const filtered = useMemo(
  () => tasks.filter(task => task.status === status),
  [tasks, status]
);
```

If the data is from Redux:

```tsx
const filtered = useAppSelector(state =>
  selectTasksByStatus(state, status)
);
```

### 2. Use event handlers for user actions

Bad:

```tsx
const [shouldSave, setShouldSave] = useState(false);

useEffect(() => {
  if (!shouldSave) return;
  saveTask(taskId);
  setShouldSave(false);
}, [shouldSave, taskId]);

return <button onClick={() => setShouldSave(true)}>Save</button>;
```

Good:

```tsx
return <button onClick={() => saveTask(taskId)}>Save</button>;
```

### 3. Use query/data libraries for fetching

Bad:

```tsx
useEffect(() => {
  let cancelled = false;
  fetchTask(taskId).then(task => {
    if (!cancelled) setTask(task);
  });
  return () => { cancelled = true; };
}, [taskId]);
```

Good:

```tsx
const { data: task } = useQuery({
  queryKey: ["task", taskId],
  queryFn: () => fetchTask(taskId),
});
```

For database-backed or reactive UIs, prefer watch-query bridges, active cache sync hooks, or standard query hooks rather than component-local fetch effects.

### 4. Reset with key/remount when identity changes

Bad:

```tsx
useEffect(() => {
  setDraftTitle(task.title);
}, [task.id]);
```

Good:

```tsx
<TaskEditor key={task.id} task={task} />
```

Use this when a component should behave like a fresh instance per entity.

### 5. Use explicit mount-only external sync wrappers

Legitimate effects include DOM integration, subscriptions, third-party widget setup, browser APIs, observers, imperative animation lifecycle, or external systems.

Prefer an explicit wrapper such as `useMountEffect`, `useSubscription`, `useResizeObserver`, or a domain-specific hook so intent is visible and raw `useEffect` does not spread.

## Do not hide effects in generic hooks

Bad cleanup:

```tsx
useSyncedState(value, setValue);
```

This only hides the same synchronization smell.

Good cleanup makes ownership clear:

```tsx
const derivedValue = deriveValue(value);
```

or:

```tsx
const subscription = useWorkspaceSubscription(workspaceId);
```

## Stop conditions

Stop and report when an effect controls:

- external subscriptions without a known replacement
- imperative widgets or DOM APIs
- animation lifecycle
- worker lifecycle
- socket or broadcast channel lifecycle
- persistence/sync behavior
- calendar/recurrence expansion or drag-and-drop side effects

These may need a domain hook, not simple deletion.

## Verification

Verify render count if the effect previously caused extra renders, test event behavior, test mount/unmount cleanup, test identity changes, and run lint/typecheck. If replacing effect fetches, verify cancellation/stale behavior is still handled by the new owner.
