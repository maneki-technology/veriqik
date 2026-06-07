# 0004 Public Check and Internal Eval Boundary

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik will expose public authorization checks only as permission checks:

```text
check(subject, object, permission)
```

Internal execution may evaluate either permissions or relations through a tagged `eval` target:

```text
eval(subject, object, permission(permission))
eval(subject, object, relation(relation))
```

## Context

Veriqik's core semantic distinction is:

```text
relation = tuple-backed stored relationship
permission = compiled authorization program
```

Writes target relations. Public checks target permissions. Internal userset expansion and traversal still need relation evaluation.

## Considered Options

- Let public `check` target both relations and permissions.
- Expose separate public `check_relation`.
- Keep relation evaluation internal, with optional debug/admin tooling later.

## Rationale

Keeping public checks permission-only preserves the product distinction between stored relationships and computed authorization programs.

Relation evaluation is an engine primitive, not the application authorization API. Debug/admin tooling may expose relation evaluation later, but it must not become the stable public check surface.

## Consequences

- Public clients cannot accidentally depend on relation checks as authorization decisions.
- Schema authors must define permissions for application-facing access checks.
- The check engine still needs internal relation evaluation for usersets, traversal, memoization, cycle detection, and explain paths.
- Error handling must reject relation names passed as public check targets.

## Confidence

High.

Reevaluate only if real usage shows a separate public debug API is needed, not as a replacement for permission checks.

## Supersedes

None.

## Superseded By

None.
