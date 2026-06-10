# 0002 Use a Zed-Inspired Veriqik DSL

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik will define its own compact ReBAC DSL, inspired by SpiceDB's Zed schema language rather than OpenFGA's model format.

Veriqik will not target full SpiceDB DSL compatibility in MVP 1. The DSL should preserve familiar relation/permission semantics where they help, while remaining free to choose Veriqik-specific syntax, constraints, AST shape, error behavior, and execution semantics.

## Context

SpiceDB's DSL is a strong reference point. It already has first-class `relation` and `permission` concepts, a mature operator model, caveats, arrows, schema tooling, and production use.

OpenFGA is also Zanzibar-inspired, but its model format is more verbose and does not make the same first-class distinction between relation and permission in the way Veriqik wants to expose the domain.

Veriqik's DSL must serve the database engine, not only the user-facing schema surface. The language should compile cleanly into native AST, planner, evaluator, index, memoization, and explanation structures.

## Considered Options

- Adopt SpiceDB's Zed DSL as-is.
- Build a Veriqik DSL inspired by Zed.
- Use OpenFGA-compatible models.
- Invent a DSL without using existing FGA languages as a reference.

## Rationale

Zed is the best existing reference because it is concise, relation/permission aware, and proven in real ReBAC systems.

Full compatibility is not the right MVP 1 goal. It would force Veriqik to inherit every SpiceDB semantic edge case before the storage engine, planner, and evaluator have proven their own shape.

The proposed direction is to reuse the mature ideas, not the compatibility contract:

- `relation` means stored relationship edge
- `permission` means compiled authorization program
- common operators should feel familiar
- advanced features, including caveats, can be deferred until the engine needs them
- explanations, failed-closed behavior, and revision semantics remain Veriqik-owned

## Consequences

- Veriqik reduces DSL design risk by borrowing from the strongest existing ReBAC language.
- Users familiar with SpiceDB should find the core concepts recognizable.
- Veriqik avoids promising SpiceDB compatibility before the engine exists.
- Some migration/import use cases will require explicit translation instead of direct reuse.
- The DSL spec must clearly mark which Zed-inspired features are in MVP 1 and which are deferred.

## Confidence

Medium.

Reevaluate if MVP 1 users strongly need direct SpiceDB schema compatibility, or if the Veriqik engine design diverges enough that Zed-inspired syntax becomes misleading.

## Supersedes

None.

## Superseded By

None.
