# De-Prop Reference

Use this reference when cleaning React/Redux prop APIs, reducing prop drilling, replacing ambiguous booleans, or deciding whether context, selectors, composition, or semantic variants would be safer than passing more props.

## Contents

1. De-prop definition
2. Prop ownership rules
3. Prop smell catalog
4. Context vs props vs selectors
5. Fix patterns
6. Stop conditions
7. Review phrases

## 1. De-prop definition

De-prop removes accidental or incorrect prop complexity while preserving component behavior. It turns vague, conflicting, manually pushed props into deterministic, semantically owned APIs.

De-prop is not “use context everywhere.” Props are still the correct tool for direct parent-child data, local configuration, explicit callbacks, slots, and standard DOM attributes. Context and Redux selectors are only better when they reduce repeated plumbing without hiding ownership or increasing render cost.

## 2. Prop ownership rules

Use these rules before changing any prop API:

- A prop should describe one clear decision owned by the caller.
- A component should derive visual state from canonical values when possible.
- Mutually exclusive states should be encoded as a single enum/string-union prop, not multiple booleans.
- Standard UI primitives should forward valid DOM props unless there is a deliberate safety reason not to.
- Parent components should not push derived flags that can disagree with source state.
- Avoid passing large entity objects through many layers when an ID plus selector at the ownership boundary is safer.
- Avoid context for high-frequency per-row or per-cell state unless the provider is scoped and render behavior is verified.

## 3. Prop smell catalog

### Magic boolean props

Symptoms:

```tsx
<Button isPrimary isGhost />
<Card compact dense elevated active selected />
```

Why it smells:

- states can conflict
- precedence becomes hidden in implementation order
- callers must know which boolean “wins”
- adding one more visual mode creates another flag

Preferred fix:

```tsx
<Button intent="primary" />
<Button intent="ghost" />
<Card density="compact" emphasis="elevated" state="selected" />
```

Use semantic enums or CVA-style variants for mutually exclusive choices. Split props by axis when the choices are independent: `intent`, `size`, `density`, `tone`, `emphasis`, `state`.

### Manual derived-state props

Symptoms:

```tsx
<StatusOption label="Online" isActive={presence === 'online'} />
<DropdownMenuItem isChecked={presence === s.value} />
```

Why it smells:

- visual truth can drift from canonical state
- callers repeatedly implement comparison logic
- tests must cover each caller rather than the component contract

Preferred fix:

```tsx
<StatusOption value="online" currentValue={presence} />

<DropdownMenuItem
  endSlot={presence === s.value ? <Icon icon={Check} aria-hidden /> : null}
/>
```

For option-like components, pass canonical values and derive the visual state inside the component. For generic menu primitives, prefer explicit slots when the primitive should not know domain semantics.

### Prop drilling

Symptoms:

- the same prop passes through 3+ layers unchanged
- intermediate components do not use the prop
- callbacks are threaded through layout shells only to reach a leaf
- view/controller metadata appears in many unrelated prop signatures

Preferred fixes:

- use context for stable subtree concerns such as density, theme, current view scope, controller, command bus, or workspace shell metadata
- use Redux selectors for entity data when a leaf owns the read boundary
- use composition/slots to pass rendered pieces instead of many configuration flags
- keep explicit props when only one parent-child hop is involved

### Prop explosion

Symptoms:

```tsx
<TaskCard
  task={task}
  project={project}
  workspace={workspace}
  showAvatar
  showProject
  enableDrag
  enableInlineEdit
  allowRecurrence
  onOpen={onOpen}
  onMove={onMove}
  onArchive={onArchive}
  onAssign={onAssign}
/>
```

Why it smells:

- the component may own too many responsibilities
- the caller has to understand internal branches
- small UI changes require touching many call sites

Preferred fixes:

- split domain-specific behavior into containers and presentational primitives
- group stable semantic axes only when the group has a real concept
- use slots for optional UI regions
- keep command callbacks behind a single domain command API only if that API already exists

### Class fighting props

Symptoms:

```tsx
<button className={`p-2 ${isLarge ? 'p-4' : ''} ${className}`} />
```

Why it smells:

- Tailwind utilities can conflict
- visual precedence depends on string order
- callers can accidentally override internal states

Preferred fix:

```tsx
<button className={cn(baseClasses, sizeClasses[size], stateClasses[state], className)} />
```

Use `cn()` or the project-standard class merge helper for dynamic class strings. Put `className` last only when external override is allowed. Put critical state classes later when the primitive must enforce disabled/error/selected visuals.

### Default-value noise

Symptoms:

```tsx
function Icon(props: IconProps) {
  const size = props.size === undefined ? 16 : props.size;
  const tone = props.tone || 'default';
}
```

Preferred fix:

```tsx
function Icon({ size = 16, tone = 'default', ...props }: IconProps) {
  // ...
}
```

Use signature defaults for `undefined`. Use `??` when preserving valid falsy values matters. Avoid `||` for defaults when `0`, `false`, or an empty string are valid inputs.

### Missing prop propagation

Symptoms:

```tsx
type ButtonProps = {
  intent?: 'primary' | 'ghost';
  onClick?: () => void;
};
```

Why it smells:

- consumers lose standard DOM attributes
- accessibility props get blocked
- primitive wrappers require endless manual prop additions

Preferred fix:

```tsx
type ButtonProps = Omit<React.ComponentPropsWithoutRef<'button'>, 'type'> & {
  intent?: 'primary' | 'ghost';
};

function Button({ intent = 'primary', className, type = 'button', ...props }: ButtonProps) {
  return <button type={type} className={cn(buttonVariants({ intent }), className)} {...props} />;
}
```

Forward standard props on primitives. Be deliberate about spread order. Internal safety defaults like `type="button"` should not be accidentally lost. If handlers must be combined, compose them explicitly rather than overwriting either side.

### Config-object slop

Symptoms:

```tsx
<Panel config={{ showHeader: true, mode: 'compact', enableActions: true }} />
```

Why it smells:

- object identity may be unstable
- the config often duplicates props with worse typing
- one-off config bags hide what the caller controls

Preferred fix:

- use explicit semantic props for a small primitive
- use a typed preset only when multiple call sites share the preset
- memoize or hoist config only if object identity matters and the abstraction is worth keeping

## 4. Context vs props vs selectors

### Keep props when

- data moves one or two layers
- the parent truly owns the value
- the prop is local UI configuration
- the component is presentational and should remain reusable
- the value changes frequently and explicit prop flow is cheaper than provider churn

### Use context when

- the value is stable across a subtree
- many intermediate components only pass it through
- the value represents environment, not item data
- examples: theme, density, locale, view scope, workspace ID, controller API, command dispatcher, permission reader

Avoid placing rapidly changing list item state, hover state, input text, or per-cell values in broad context providers unless scoped and measured.

### Use Redux selectors when

- the canonical source is normalized app state
- the leaf can read by ID without receiving a large object
- drilling entity data causes stale props or wide rerenders
- selector memoization and reference stability are understood

Do not create selector factories inside render without need. Keep Reselect input selectors simple and place calculations in result functions.

### Use composition or slots when

- the caller needs to supply optional visual regions
- a primitive should not know domain rules
- multiple booleans only control whether something appears

Example:

```tsx
<DropdownMenuItem
  label={s.label}
  endSlot={presence === s.value ? <Icon icon={Check} aria-hidden /> : null}
/>
```

Slots are often cleaner than `showCheck`, `isChecked`, `rightIcon`, `rightLabel`, and `badgeCount` all competing inside one primitive.

## 5. Fix patterns

### Magic booleans to semantic variants

Before:

```tsx
<Button isPrimary isGhost />
```

After:

```tsx
<Button intent="primary" />
<Button intent="ghost" />
```

Behavior rule: preserve the old winning precedence during migration. If old behavior allowed conflict, map each existing call site to the visual mode it actually produced before deleting booleans.

### Caller-derived state to canonical value

Before:

```tsx
<SegmentedOption isActive={value === option.value} onClick={() => onChange(option.value)} />
```

After:

```tsx
<SegmentedOption value={option.value} currentValue={value} onSelect={onChange} />
```

Inside:

```tsx
const isActive = currentValue === value;
```

Only do this when the component semantically owns option selection. If it is a generic primitive, use `aria-selected`, `data-state`, or a slot rather than adding domain-specific state.

### Prop drilling to context

Before:

```tsx
<WorkspaceShell density={density} controller={controller}>
  <ProjectLayout density={density} controller={controller}>
    <Toolbar density={density} controller={controller} />
  </ProjectLayout>
</WorkspaceShell>
```

After:

```tsx
<WorkspaceViewProvider density={density} controller={controller}>
  <WorkspaceShell>
    <ProjectLayout>
      <Toolbar />
    </ProjectLayout>
  </WorkspaceShell>
</WorkspaceViewProvider>
```

Use this only when `density` and `controller` are true subtree environment values. Do not place task row data into this broad provider.

### Entity blob to ID + selector

Before:

```tsx
<TaskRow task={task} project={project} assignees={assignees} />
```

Potential after:

```tsx
<TaskRow taskId={task.id} />
```

Inside the row, use existing selectors to read normalized entities. This can reduce prop plumbing, but it is not automatically better. Verify selector cache behavior, row rerenders, and list virtualization assumptions.

### Primitive prop forwarding

Before:

```tsx
function IconButton({ icon, onClick }: Props) {
  return <button onClick={onClick}>{icon}</button>;
}
```

After:

```tsx
type IconButtonProps = React.ComponentPropsWithoutRef<'button'> & {
  icon: React.ReactNode;
};

function IconButton({ icon, type = 'button', ...props }: IconButtonProps) {
  return <button type={type} {...props}>{icon}</button>;
}
```

Check spread order, default preservation, ref forwarding, disabled behavior, accessibility attributes, and event handler composition.

## 6. Stop conditions

Stop and report instead of editing when:

- replacing props requires a public component API migration across many call sites
- context would become a hidden global dependency
- moving reads to Redux selectors may change render timing or memoization behavior
- a visual boolean encodes two different domain rules in different call sites
- a prop exists for accessibility, testing, portal behavior, or integration contracts
- deleting a prop would break downstream consumers outside the current scope

## 7. Review phrases

Use these when reporting de-prop decisions:

- “Replaced conflicting boolean flags with a single semantic variant so impossible states are unrepresentable.”
- “Kept this as a prop because the parent owns the decision and the value only travels one layer.”
- “Moved repeated environment props into scoped context; avoided putting per-row state into context.”
- “Derived selected state from canonical value rather than accepting a manually pushed `isSelected` flag.”
- “Preserved primitive prop forwarding so accessibility and standard DOM attributes still work.”
- “Skipped this de-prop because changing the public prop API would require a wider migration.”
