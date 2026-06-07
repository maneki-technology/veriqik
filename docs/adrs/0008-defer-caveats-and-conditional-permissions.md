# 0008 Defer Caveats and Conditional Permissions

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik will not include caveats or conditional permissions in MVP1.

MVP1 permission evaluation is based on schema-defined ReBAC relationships and compiled permission expressions only. Request context, environmental attributes, tuple conditions, and time-based predicates are deferred.

## Context

Caveats and conditional permissions allow an authorization result to depend on context outside the relationship graph, such as request attributes, time, IP range, device posture, tenant policy flags, or other application-provided values.

This is valuable, but it changes the core shape of the system:

- check requests need structured context
- tuples may need attached conditions
- cache keys must include normalized context
- explanations must report condition evaluation
- failed-closed behavior must distinguish false conditions from missing or invalid context
- indexes and materialization need to account for conditional edges

SpiceDB supports caveats, so this is part of the mature design space. Veriqik should reserve room for it without taking on the complexity before the core database engine is proven.

## Considered Options

- Include caveats in MVP1.
- Include only time-based conditions in MVP1.
- Defer caveats and conditional permissions.
- Exclude caveats permanently.

## Rationale

MVP1 should prove the core Veriqik loop first: schema compile, relationship writes, WAL, indexes, revisioned checks, explain paths, and recovery.

Caveats introduce a second evaluation language and a second source of authorization truth. Adding them too early would make correctness, caching, explanations, and benchmarks harder to interpret.

Deferring caveats keeps MVP1 simpler while preserving the future direction:

- schema syntax can reserve caveat-related keywords
- tuple storage can leave room for optional condition metadata
- check APIs can later add structured context
- cache/memoization design can require context-aware keys when conditions exist
- unsupported caveated schemas or tuples must fail closed

## Consequences

- MVP1 cannot model contextual ABAC rules directly.
- Applications needing contextual checks must keep those checks outside Veriqik for now.
- The MVP1 benchmark surface is cleaner because checks depend only on stored relationships and schema programs.
- Future caveat support will require explicit updates to the DSL, tuple format, check API, evaluator, explanation model, and cache keys.

## Confidence

Medium.

Reevaluate if early users cannot model critical authorization cases without caveats, or if a minimal condition model becomes necessary to compare fairly with SpiceDB.

## Supersedes

None.

## Superseded By

None.
