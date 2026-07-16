# De-state Reference

Use de-state when a refactor involves duplicated state, mirrored props, stored derived values, stale local state, Redux state shape, canonical values, or source-of-truth cleanup.

## Goal

Reduce state to the smallest canonical set that can produce the UI and behavior deterministically.

Do not remove state merely because it looks redundant. Some state is legitimate when it represents user input in progress, local disclosure/focus, transient drag state, optimistic mutations, or an external system lifecycle.

## Smells

- `useState` initialized from props and synchronized later.
- State that mirrors Redux, URL params, query results, or entity data.
- `useEffect(() => setX(deriveFromY(y)), [y])`.
- Separate `isActive`, `isSelected`, `isChecked`, or `hasX` state when a canonical value already exists.
- Redux storing filtered/sorted/grouped lists that can be derived by selectors.
- Local component state and global state both claiming ownership of the same value.
- Multiple booleans representing one finite state machine.
- Nested copies of related entities instead of IDs.
- Manual cache fields without invalidation ownership.

## Preferred fixes

### Derive render state inline

Bad:

```tsx
const [isSelected, setIsSelected] = useState(task.id === selectedTaskId);

useEffect(() => {
  setIsSelected(task.id === selectedTaskId);
}, [task.id, selectedTaskId]);
```

Good:

```tsx
const isSelected = task.id === selectedTaskId;
```

### Move shared derived state into selectors

Bad:

```tsx
const visibleTasks = tasks.filter(task => task.projectId === projectId && !task.archived);
```

Good:

```tsx
const visibleTasks = useAppSelector(state =>
  selectVisibleTasksForProject(state, projectId)
);
```

### Replace boolean clusters with one state value

Bad:

```ts
type PanelState = {
  isOpen: boolean;
  isClosing: boolean;
  isAnimating: boolean;
};
```

Good:

```ts
type PanelPhase = "closed" | "opening" | "open" | "closing";
```

### Keep legitimate local state local

Keep state local when it is UI-only and not needed elsewhere:

```tsx
const [isMenuOpen, setIsMenuOpen] = useState(false);
const [draftTitle, setDraftTitle] = useState(initialTitle);
```

Draft state is legitimate if it intentionally diverges from saved canonical state until submit/cancel.

## Redux-specific guidance

Redux should hold normalized canonical entities and durable UI runtime state that must be shared or restored. It should not hold every computed list or visual flag.

Prefer:

- entity adapters for canonical records
- IDs for relationships
- selectors for derived lists/counts/groups
- explicit mutation gateways for writes
- local state for short-lived component-only state

Avoid:

- storing filtered task IDs for every view if selectors can derive them
- storing both `status` and `isDone`
- nesting full child records inside parent records
- copying database rows into multiple store slices with competing ownership

## Stop conditions

Stop and report instead of changing state shape when:

- the change requires migration or persistence changes
- optimistic updates or rollback semantics are involved
- collaboration/sync conflict behavior could change
- external APIs depend on the current shape
- tests do not cover the canonical behavior
- the state may be intentionally denormalized for performance and no benchmark exists

## Verification

Verify with typecheck, UI smoke path, state transition tests, selector tests, and stale-state regression checks. For Redux changes, inspect reference stability and recomputation if selectors are affected.
