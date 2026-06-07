# 0002 Build a Domain-Specific Authorization Database

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik will be built as a domain-specific database for fine-grained authorization, rather than as a thin authorization layer on top of an existing FGA product, general-purpose RDBMS, document database, or graph database.

Veriqik will own authorization-specific schema semantics, relationship storage, indexes, revisions, checks, explanations, recovery, and eventually replication.

The FGA domain engine will not call a separate database over the network for normal check/eval execution. Checks, evaluation, indexes, WAL, checkpoints, and revision state are part of the same local database boundary. Network APIs may exist for clients and benchmarks, but not as the internal boundary between authorization logic and storage.

## Context

Fine-grained authorization using ReBAC has domain-specific needs:

- writes target relationships
- checks target permissions
- revocations need freshness guarantees
- relationship traversal must be bounded
- explanation is a product feature
- indexes are shaped around authorization checks
- distributed reads must distinguish committed, applied, and published revisions

OpenFGA and SpiceDB are the closest open-source reference points. They are mature Zanzibar-inspired authorization engines with network APIs, client tooling, modeling support, configurable consistency, and pluggable datastore backends.

OpenFGA and SpiceDB are strong choices when the goal is to adopt an existing FGA service and ecosystem. Veriqik is exploring a different product bet: a purpose-built authorization database with native Veriqik semantics and database guarantees.

## Considered Options

- Use OpenFGA, SpiceDB, or another existing FGA product directly.
- Build a Veriqik API layer on top of PostgreSQL or another RDBMS.
- Build on a graph database.
- Build a domain-specific authorization database.

## Rationale

The core Veriqik idea is that authorization logic, relationship storage, indexing, consistency, and explainability belong together in one purpose-built database.

Using OpenFGA, SpiceDB, or a general-purpose database would reduce early implementation cost, but it would also constrain Veriqik to another system's model or push the hardest authorization behavior into application code.

The main gaps Veriqik intends to close are:

- **Native relation/permission split:** `relation` is a stored edge; `permission` is a compiled authorization program.
- **Engine-oriented DSL:** Veriqik can borrow proven Zed concepts while compiling schemas into Veriqik-owned AST, planner, evaluator, index, memoization, and explanation structures.
- **Database-owned authorization state:** WAL, checkpoints, indexes, revisions, health, and recovery are part of one authorization state machine.
- **No internal FGA-to-DB network hop:** check/eval should execute against local Veriqik state, not through a separate storage service API.
- **Revision-first consistency:** checks should report evaluated revisions, and future distributed reads should use revision tokens for read-after-revoke.
- **Failed-closed semantics:** authorization uncertainty should be distinguishable from clean denial.
- **Core explainability and profiling:** proof paths, stats, and eventually branch-level performance data should be part of the database contract.

## Performance Tradeoffs

OpenFGA and SpiceDB use datastore indexes from their configured backends plus in-memory caching around repeated authorization work. SpiceDB in particular has strong production-oriented features: ZedTokens, configurable consistency, dispatch caching, schema caching, clustered dispatch, caveats, watch APIs, and optional materialized acceleration.

This is flexible and mature. The tradeoff is that the authorization engine still sits above a general-purpose datastore abstraction.

Veriqik trades that flexibility for specialization:

- native authorization indexes derived from WAL/checkpoints
- check hot paths over binary keys instead of generic datastore rows
- no internal network hop between the authorization evaluator and storage/index state
- permission-aware planning and profiling
- revision-aware memoization and caching
- batch-first evaluation with shared memoized subproblems
- future selective materialization of hot permissions

These are potential advantages, not proven ones. They must be validated with benchmarks against OpenFGA, SpiceDB, and other systems.

## Consequences

- Veriqik must implement database fundamentals: WAL, checkpoints, recovery, indexes, revisions, health, and eventually replication.
- Early implementation cost is higher than adopting OpenFGA, SpiceDB, or PostgreSQL directly.
- Veriqik can expose simpler native semantics instead of inheriting another product's model.
- Performance work can optimize around check/eval workloads rather than generic SQL, graph queries, or pluggable datastore abstractions.
- Correctness burden moves into Veriqik; tests must cover database behavior, not only authorization logic.

## Confidence

Medium.

This is the central product bet. Reevaluate if early implementation shows the database work dominates the authorization value, or if an existing product can support Veriqik's relation/permission semantics, explainability, freshness model, and performance goals without compromising the design.

## References

- [OpenFGA GitHub repository](https://github.com/openfga/openfga)
- [OpenFGA usersets documentation](https://openfga.dev/docs/modeling/building-blocks/usersets)
- [OpenFGA roles and permissions documentation](https://openfga.dev/docs/modeling/roles-and-permissions)
- [OpenFGA query consistency modes](https://openfga.dev/docs/interacting/consistency)
- [OpenFGA storage configuration](https://openfga.dev/docs/getting-started/setup-openfga/configure-openfga)
- [SpiceDB GitHub repository](https://github.com/authzed/spicedb)
- [SpiceDB consistency documentation](https://authzed.com/docs/spicedb/concepts/consistency)
- [SpiceDB performance documentation](https://authzed.com/docs/spicedb/ops/performance)
- [SpiceDB querying documentation](https://authzed.com/docs/spicedb/concepts/querying-data)

## Supersedes

None.

## Superseded By

None.
