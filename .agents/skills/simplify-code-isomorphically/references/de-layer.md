# De-layer Reference

Use de-layer when code crosses architectural boundaries: UI writes persistence, selectors perform domain mutations, domain utilities import UI, infrastructure leaks upward, or calendar/worker/sync logic appears in the wrong place.

## Goal

Put behavior in the layer that owns it. Boundaries are more important than line count.

## Common layers

- **UI/render**: present data, capture user intent, expose accessible interactions.
- **View/controller**: scope data, compose view behavior, connect UI to domain commands.
- **State/read model**: normalized hot UI cache, selectors, view state.
- **Domain logic**: policies, validation, state transitions, invariants.
- **Mutation gateway/commands**: derive/validate write intent, optimistic update, persistence commit, rollback.
- **Infrastructure**: databases, remote APIs, local storage, file systems, workers.
- **Engines/workers**: recurrence expansion, drag math, expensive projections, background processing.

## Smells

- React component calls database query methods, `fetch`, Supabase/API clients, or filesystem APIs directly.
- Component imports SQL/query strings or storage adapters.
- Selector imports mutation commands or API clients.
- Domain utility imports React components, icons, CSS, or hooks.
- UI components contain permission policy, recurrence expansion, sync conflict handling, or migration logic.
- Worker/engine behavior is duplicated in render components.
- Shared utility folders become dependency dumping grounds.
- Two layers both own the same transformation.

## Preferred fixes

### Move writes behind commands

Bad:

```tsx
function TaskCard({ task }) {
  async function handleMove(nextStart: string) {
    await db.execute("UPDATE tasks SET start_at = ? WHERE id = ?", [nextStart, task.id]);
    dispatch(taskMoved({ id: task.id, startAt: nextStart }));
  }
}
```

Good:

```tsx
function TaskCard({ task }) {
  const moveTask = useMoveTaskCommand();
  return <Card onMove={nextStart => moveTask({ taskId: task.id, nextStart })} />;
}
```

The command owns validation, optimistic update, persistence, rollback, and error handling.

### Move policy out of render

Bad:

```tsx
const canDelete = user.role === "owner" || task.createdBy === user.id;
```

Better:

```tsx
const canDelete = useAppSelector(state =>
  selectCanDeleteTask(state, task.id)
);
```

Or use a domain policy helper if no Redux state is needed.

### Keep engines authoritative

Bad:

```tsx
const occurrences = expandRRule(event.rrule, visibleRange);
```

inside a month cell renderer.

Good:

```tsx
const occurrences = useCalendarOccurrences(visibleRange);
```

where expansion is owned by the calendar engine/worker pipeline.

## Circular dependency cleanup

Circular dependencies often mean shared code lives in the wrong layer.

Do not automatically merge modules. Prefer:

- move shared constants/types to a lower-level domain module
- split UI-only exports from domain exports
- invert dependency through command interface
- move cross-cutting logic into a clear owner package

## Stop conditions

Stop and report when boundary cleanup requires:

- changing command contracts
- changing storage or sync behavior
- moving data ownership between slices/modules
- changing engine/worker APIs
- altering permission or calendar semantics
- broad import graph surgery without tests

## Verification

Run typecheck, affected tests, smoke the user action, and verify no direct infrastructure imports remain in UI after the move. For persistence/sync changes, verify optimistic, rollback, offline, and retry behavior.
