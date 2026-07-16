# De-type Reference

Use de-type when cleaning unsafe, loose, duplicated, or stringly typed contracts while preserving runtime behavior and public APIs.

## Goal

Make invalid states harder to represent without causing unnecessary API churn.

Type cleanup should clarify contracts that already exist. Do not invent a new domain model during a behavior-preserving refactor.

## Smells

- `any`, `unknown` cast to concrete type without validation, or `as Foo` hiding bad data.
- `Record<string, any>` or config blobs with undocumented keys.
- `variant?: string`, `status?: string`, `type?: string` when the allowed values are finite.
- Multiple duplicated unions for the same concept.
- Booleans representing mutually exclusive modes.
- Optional fields that are only valid for certain kinds but not modeled as a discriminated union.
- Primitive obsession: many loose strings/booleans/numbers travel together as an implicit object.
- Type guards duplicated across files.
- Runtime schema and TypeScript type drift.

## Safe fixes

### Replace stringly props with finite unions

Bad:

```ts
type ButtonProps = {
  variant?: string;
  size?: string;
};
```

Good:

```ts
type ButtonIntent = "primary" | "ghost" | "danger";
type ButtonSize = "sm" | "md" | "lg";

type ButtonProps = {
  intent?: ButtonIntent;
  size?: ButtonSize;
};
```

### Replace boolean clusters with discriminants

Bad:

```ts
type ToastProps = {
  isSuccess?: boolean;
  isError?: boolean;
  isWarning?: boolean;
};
```

Good:

```ts
type ToastTone = "success" | "error" | "warning" | "info";

type ToastProps = {
  tone?: ToastTone;
};
```

### Model variant-specific fields

Bad:

```ts
type Field = {
  kind: "text" | "select";
  placeholder?: string;
  options?: string[];
};
```

Good:

```ts
type Field =
  | { kind: "text"; placeholder?: string }
  | { kind: "select"; options: string[] };
```

### Use shared domain types

If `TaskStatus`, `ProjectStatus`, or `DocumentStatus` already exists, import it. Do not recreate the union locally.

## Runtime validation

Types do not validate remote, persisted, or user-provided data. If data crosses a boundary, use the existing parser/schema/validator rather than only adding TypeScript types.

Bad:

```ts
const payload = response.json() as TaskPayload;
```

Better:

```ts
const payload = TaskPayloadSchema.parse(await response.json());
```

Only add new runtime schemas when that pattern already exists or the user requested boundary hardening.

## Public API caution

Changing a public type can be behavior-preserving internally but breaking externally. Preserve exported names and accepted inputs unless explicitly asked.

For component internals, you can often add stronger internal types while keeping public props stable.

## Stop conditions

Stop and report when type cleanup requires:

- public API renames
- database schema changes
- migration of persisted enum values
- changing backend payloads
- changing status/state machine semantics
- adding a new validation library
- rewriting broad domain models

## Verification

Run typecheck and affected tests. For runtime schemas, test valid and invalid boundary payloads. For discriminated unions, verify all render branches still cover the same cases.
