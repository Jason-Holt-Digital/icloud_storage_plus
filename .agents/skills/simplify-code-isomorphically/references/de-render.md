# De-render Reference

Use de-render when cleaning React render churn, unstable props, context rerender storms, unnecessary memoization, expensive render-time derivation, heavy list items, or excessive reactive surface area.

## Goal

Make rendering predictable and cheap without turning the codebase into memoization soup.

Do not memoize everything. Stabilize references when they cross a boundary that cares: `memo` children, context provider values, dependency arrays, virtualization/list rows, selectors, or expensive calculations.

## Smells

- Provider value object created inline every render.
- Passing object/array literals to memoized children.
- Passing inline functions to heavy list rows without reason.
- Parent component reads too much state and rerenders a huge subtree.
- List item receives large objects when it only needs an ID.
- Context stores high-frequency per-row state.
- Selector returns fresh arrays/objects and triggers rerenders.
- Expensive sort/filter/group work runs on every render.
- `useMemo`/`useCallback` everywhere but not protecting a real boundary.
- `React.memo` used while props are always unstable.

## Preferred fixes

### Stabilize provider values

Bad:

```tsx
return (
  <ViewContext.Provider value={{ density, setDensity, scope }}>
    {children}
  </ViewContext.Provider>
);
```

Good:

```tsx
const value = useMemo(
  () => ({ density, setDensity, scope }),
  [density, setDensity, scope]
);

return <ViewContext.Provider value={value}>{children}</ViewContext.Provider>;
```

Only do this when the provider has meaningful consumers and rerender scope matters.

### Pass IDs to list rows when rows can select their own data

Bad:

```tsx
{taskIds.map(id => (
  <TaskRow key={id} task={tasksById[id]} project={project} />
))}
```

Better when Redux is the hot read model:

```tsx
{taskIds.map(id => (
  <TaskRow key={id} taskId={id} />
))}
```

Then `TaskRow` selects exactly what it needs.

### Memoize expensive local derivation

```tsx
const groupedTasks = useMemo(
  () => groupTasksByStatus(tasks),
  [tasks]
);
```

If many components need the same derived data, prefer a selector instead.

### Avoid false optimization

Bad:

```tsx
const label = useMemo(() => title.trim(), [title]);
```

Good:

```tsx
const label = title.trim();
```

Tiny derivations do not need memoization unless reference stability is required.

## Context caution

Context is not a universal prop-drilling fix. Context rerenders all consumers when the provider value changes unless split or stabilized.

Use context for stable scoped environment values: theme, density, workspace scope, command API, feature flags, controller metadata.

Avoid context for high-frequency entity state: task row hover, active cell, per-item completion, drag position, rapidly changing selection unless the provider is intentionally scoped and optimized.

## Stop conditions

Stop and measure before changing when:

- no render performance problem is observed
- the change adds broad memoization complexity
- reference stability is part of a selector or context contract you do not understand
- virtualization, drag-and-drop, animation, or calendar grids are involved
- the fix would move state ownership

## Verification

Use React Profiler, render count logs, interaction smoke tests, selector recomputation checks, and visual tests. Verify the optimization does not stale closures, break keyboard/focus behavior, or hide updates.
