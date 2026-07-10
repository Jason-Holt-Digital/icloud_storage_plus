# De-selector Reference

Use de-selector when cleaning Redux, Reselect, derived data, inline `useSelector` calculations, selector reference stability, parameterized selectors, recomputation problems, or normalized entity reads.

## Goal

Keep data derivation in the correct layer, with stable inputs and stable outputs where consumers depend on referential equality.

Selectors should make UI reads cheap and predictable. They should not become junk drawers for domain mutations, persistence writes, rendering decisions, or unstable object construction.

## Smells

- Components doing `.map().filter().sort()` directly inside `useSelector`.
- Multiple components repeat the same entity filtering logic.
- Selectors return fresh arrays/objects every call without memoization.
- Parameterized selectors thrash because one shared selector sees many IDs/args.
- Input selectors perform expensive calculations.
- Input selectors return new arrays/objects.
- Selectors mix unrelated domains or know too much about component rendering.
- Selector output includes JSX or UI component instances.
- Derived lists are stored in Redux instead of derived from normalized entities.

## Reselect rules

Keep input selectors simple and stable:

```ts
const selectTasksState = (state: RootState) => state.tasks;
const selectProjectIdArg = (_state: RootState, projectId: string) => projectId;
```

Put calculations in the result function:

```ts
export const selectTasksForProject = createSelector(
  [selectAllTasks, selectProjectIdArg],
  (tasks, projectId) => tasks.filter(task => task.projectId === projectId)
);
```

Avoid this:

```ts
export const selectTasksForProjectBad = createSelector(
  [(state: RootState, projectId: string) =>
    selectAllTasks(state).filter(task => task.projectId === projectId)
  ],
  tasks => tasks
);
```

## Parameterized selector guidance

If many component instances call one selector with different IDs, verify the memoization strategy.

Options:

- selector factory per component instance when lifecycle is bounded
- larger LRU cache when many IDs reuse one selector safely
- pre-indexed selector result when the result is shared broadly
- direct entity lookup when only one record is needed

Do not blindly create selector factories in lists without understanding instance count and memory behavior.

## Inline selector cleanup

Bad:

```tsx
const visibleTasks = useAppSelector(state =>
  state.tasks.ids
    .map(id => state.tasks.entities[id])
    .filter(task => task?.projectId === projectId && !task.archived)
);
```

Better:

```tsx
const visibleTasks = useAppSelector(state =>
  selectVisibleTasksForProject(state, projectId)
);
```

Best depends on ownership. If this is view-specific filtering, the selector may live in the view/controller selector module. If it is domain-wide task logic, place it near task selectors.

## Reference stability

Be careful with:

```ts
const selectVm = (state: RootState) => ({
  task: selectTask(state),
  project: selectProject(state),
});
```

This returns a new object each time. Use `createSelector` or split selectors if consumers depend on equality.

## What not to move into selectors

Do not move these into selectors:

- persistence writes
- command construction with side effects
- async work
- calendar recurrence expansion owned by a worker/engine
- DOM/render details
- permission mutation decisions that belong in domain policy
- data fetching

## Stop conditions

Stop and report when selector cleanup requires:

- state shape changes
- migration from denormalized to normalized entities
- changing cache strategy across many components
- changing view-controller ownership
- altering date/time, permission, recurrence, or sync semantics

## Verification

Run selector tests, typecheck, UI smoke checks, and recomputation/reference checks when possible. Watch for accidental new arrays/objects, stale memo caches, and changed item ordering.
