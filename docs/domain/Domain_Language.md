# Veriqik Domain Language

**Tagline:** A purpose-built database for fine-grained authorization.

This document defines Veriqik's ubiquitous language. Product docs, technical specs, code, tests, APIs, CLI commands, and user-facing explanations should use these terms consistently.

Veriqik is a domain-specific database for Fine-Grained Authorization (FGA) using Relationship-Based Access Control (ReBAC). It is Zanzibar-inspired at the model level and TigerBeetle-inspired at the database level, but it uses its own domain language and DSL.

For DDD entities, value objects, aggregates, and domain services, see [Domain_Model.md](Domain_Model.md).

---

## 1. Bounded Contexts

### Authorization Model

Owns the language of schemas, types, relations, permissions, subjects, objects, tuples, and checks.

Core question:

```text
Can this subject perform this permission on this object?
```

### Authorization Database

Owns durable command execution, revisions, WAL, checkpoints, recovery, indexes, idempotency, and health.

Core question:

```text
What authorization state is durably committed, indexed, and safe to evaluate?
```

### Distributed Authorization Database

Owns replication, consensus, shard leadership, committed revisions, applied revisions, follower reads, revision tokens, failover, catch-up, snapshot shipping, and shard routing.

Core question:

```text
What committed authorization state is safely replicated, applied, queryable, and fresh enough for a client request?
```

### Explainability

Owns proof paths, decision status, failed-closed results, and execution stats.

Core question:

```text
Why was access allowed, denied, or failed closed?
```

### Operations and Benchmarking

Owns health states, debug/admin tooling, load tests, benchmark datasets, and comparison workloads.

Core question:

```text
Can Veriqik be operated, verified, and measured safely?
```

---

## 2. Core Authorization Terms

### Tenant

A namespace for schemas, tuples, dictionaries, revisions, and checks.

Rules:

- Every tuple belongs to exactly one tenant.
- Checks are tenant-scoped.
- Cross-tenant relationships are rejected in MVP 1.
- Single-tenant mode uses `tenant_id = 1`.

### Type

A schema-defined kind of object.

Examples:

```text
user
group
document
folder
tenant
```

### Object

An instance of a type.

Human format:

```text
<type>:<id>
```

Examples:

```text
user:kien
group:eng
document:doc1
folder:f1
tenant:acme
```

### Subject

The actor being evaluated for access.

A subject can be:

- a direct object, such as `user:kien`
- a userset, such as `group:eng#member`

### Relation

A tuple-backed stored relationship declared in schema.

Example:

```text
relation viewer: user | group#member
```

Rules:

- Relations are stored edges.
- Writes target relations.
- Internal evaluation may evaluate relations.
- Public `check` does not target relations.

### Permission

A compiled authorization program declared in schema.

Example:

```text
permission view = viewer + editor + parent.view
```

Rules:

- Permissions are computed, not stored.
- Public `check` targets permissions.
- Permissions do not create extra graph hops by default.
- Permissions are planning, caching, profiling, and explainability units.

### Caveat

A future conditional rule that makes a relationship or permission branch depend on request context.

Examples of caveat inputs:

- time
- IP range
- device posture
- tenant policy flags
- application-provided request attributes

Rules:

- Caveats are deferred from MVP 1.
- Unsupported caveated schemas or tuples must fail closed.
- Caveats require context-aware check inputs, cache keys, evaluation, and explanations.

### Conditional Permission

A future permission whose result may depend on caveats or request context.

MVP 1 permissions are context-free: they depend only on schema-defined ReBAC relationships and compiled permission expressions.

### Request Context

Structured values supplied with a check request for future caveat evaluation.

Examples:

- request time
- source IP
- device attributes
- application attributes

Rules:

- Request context is deferred from MVP 1.
- Request context must be normalized before it can participate in cache keys or explanations.

### Condition Context

The subset of request context visible to a specific caveat or conditional permission branch.

Rule:

- Missing, malformed, or unsupported condition context must fail closed when a condition is required.

### Context-Free Check

A check whose result depends only on stored relationships, schema programs, and the selected revision.

MVP 1 checks are context-free.

### Context-Aware Check

A future check whose result may also depend on request context and caveat evaluation.

Rules:

- Context-aware checks are deferred from MVP 1.
- Context-aware checks require context-aware memoization, cache keys, and explanations.

### Tuple

A durable relationship fact.

Human format:

```text
<object>#<relation>@<subject>
```

Examples:

```text
document:doc1#viewer@user:kien
document:doc1#viewer@group:eng#member
group:eng#member@user:kien
```

Rules:

- A tuple must target a relation, not a permission.
- A tuple must satisfy the active schema.
- A tuple is tenant-scoped.

### Grant

A write that creates access or contributes to a proof path for access.

Rules:

- A grant may be direct, such as adding `document:doc1#viewer@user:kien`.
- A grant may be indirect, such as adding `group:eng#member@user:kien` when `group:eng#member` is already a viewer.
- Read-after-grant uses the revision returned by the grant write.

### Revoke

A delete or schema change that removes access or removes a proof path for access.

Rules:

- A revoke may be direct, such as deleting `document:doc1#viewer@user:kien`.
- A revoke may be indirect, such as deleting `group:eng#member@user:kien`.
- Read-after-revoke uses the revision returned by the revoke write.

### Userset

A subject that refers to a set of subjects through another object relation.

Example:

```text
group:eng#member
```

Meaning:

```text
members of group:eng
```

### Object Relation

The pair of an object and relation.

Human format:

```text
<object>#<relation>
```

Example:

```text
document:doc1#viewer
```

### Traversal

Following a relation to another object, then evaluating a permission on that target object.

Example:

```text
parent.view
```

Meaning:

```text
Follow the local parent relation, then evaluate permission view on each parent object.
```

### Check

The public authorization query.

Form:

```text
check(subject, object, permission)
```

Rules:

- `check` is public API.
- `check` targets permissions only.
- `check(subject, object, relation)` is invalid.
- `check` returns a decision status, evaluated revision, schema version, error if failed closed, and stats.

### Eval

The internal execution primitive.

Forms:

```text
eval(subject, object, permission(permission))
eval(subject, object, relation(relation))
```

Rules:

- `eval` is not public API.
- `eval` may target relations or permissions through a tagged target.
- `eval` powers compiled permission programs, userset expansion, traversal, memoization, cycle detection, and explain path construction.

---

## 3. Decision Terms

### Allowed

The engine found a valid proof path for the requested permission.

### Denied

The engine completed evaluation and found no valid proof path.

Denied is a clean authorization result.

### Failed Closed

The engine could not safely return authorization because state or evaluation was uncertain.

Examples:

- traversal limit exceeded
- evaluation node limit exceeded
- evaluation edge limit exceeded
- requested revision unavailable
- storage unhealthy
- fatal recovery/corruption state

Failed closed is not the same as denied.

### Proof Path

One successful chain of permission and tuple events explaining why access was allowed.

### Explanation

An explanation result for an authorization decision.

MVP 1 supports:

- one successful proof path for allowed checks
- empty proof for denied checks
- error-bearing result for failed-closed checks

MVP 1 does not require full denial proof trees.

### Check Stats

Execution measurements collected during check/eval.

Examples:

- evaluation nodes visited
- evaluation edges scanned
- index lookups
- memo hits
- memo misses
- max depth reached
- elapsed time

---

## 4. Database Terms

### Command

A typed operation submitted to the state machine.

Veriqik uses `command` for state-machine requests. A command may be a write command or a read operation.

MVP commands:

- `write_schema`
- `write_relationships`
- `delete_relationships`
- `check`
- `batch_check`
- `explain_one`
- `health`
- `current_revision`

Only write commands mutate durable state.

### Write Command

A command that mutates durable authorization state and receives a revision if committed.

Examples:

- `write_schema`
- `write_relationships`
- `delete_relationships`

### Read Operation

A non-mutating API operation that evaluates or reports committed state.

Examples:

- `check`
- `batch_check`
- `explain_one`
- `health`
- `current_revision`

### Command Batch

One atomic state-machine operation that receives one revision if committed.

Examples:

- one schema write
- one relationship write batch
- one relationship delete batch

Rules:

- A committed command batch is fully visible or not visible.
- A failed command batch receives no revision.
- Relationship write/delete batches do not mix writes and deletes in MVP 1.

### Canonical Command

The deterministic representation of a write command used for idempotency and WAL encoding.

Rules:

- Human names are resolved to stable numeric IDs.
- Tuple keys and preconditions are sorted.
- Duplicate tuple keys are rejected.
- Schema text is normalized through parse/re-emit before hashing.
- The request ID is excluded from the idempotency payload hash.

### Request ID

A client-supplied idempotency key for safe write retries.

Rules:

- Scoped by `(tenant_id, command_type)`.
- Same request ID plus same canonical payload returns the original result.
- Same request ID plus different canonical payload is a conflict.

### Revision

A monotonic number assigned to each successful state-changing command batch.

Rules:

- Revisions are tenant-visible consistency tokens.
- Schema writes and relationship writes/deletes receive revisions.
- A revision is visible only after WAL durability and index application.

### Evaluated Revision

The revision captured by a check, batch check, or explain request.

Rules:

- One check uses one evaluated revision.
- One batch check uses one shared evaluated revision for all items.

### Schema Version

The version of the compiled tenant schema active at a revision.

Rules:

- Schema versions are tenant-scoped and monotonic.
- Checks report the schema version used for evaluation.
- Schema writes that invalidate existing tuples are rejected in MVP 1.

### Dictionary

A tenant-scoped mapping from human names to stable numeric IDs.

Examples:

- type names
- relation names
- permission names
- object IDs

Rules:

- Dictionary allocations are durable state-machine changes.
- IDs are never reused in MVP 1.
- Replay must reproduce the same IDs.

### WAL

Write-ahead log. The durable source of truth for committed state changes after validation.

Rules:

- WAL records are checksummed.
- WAL replay must be deterministic.
- Incomplete tail records may be truncated.
- Middle corruption is fatal until repaired or restored.

### Checkpoint

A durable snapshot of derived and committed state at one checkpoint revision.

Contains:

- current revision
- schema registry
- dictionaries
- indexes
- idempotency table

### Index

A derived data structure rebuilt from logged state.

MVP indexes:

- exists index
- forward index
- reverse index

Rules:

- Indexes are not the source of truth.
- Indexes must remain consistent after writes/deletes.
- Indexes must be rebuildable from WAL/checkpoint state.

### Health State

The operational state of the database process.

MVP health states:

- `recovering`
- `healthy`
- `read_only_storage_error`
- `degraded_checkpoint`
- `fatal_corruption`
- `shutting_down`

---

## 5. Distributed Database Terms

Distributed database terms are post-MVP vocabulary, but they should use the same domain language from the beginning.

These terms reserve language for future distributed design. They are not MVP 1 requirements unless referenced by an MVP spec or ADR.

### Server

A running Veriqik process that can host one or more replicas.

Use `server` for the Veriqik process. Use `host` for the machine, VM, container, or placement target where a server runs. Avoid `node` for distributed infrastructure because ReBAC already uses graph node/edge language.

### Replica

One copy of a shard's log-derived authorization state.

Rules:

- A replica has a committed revision, applied revision, and published revision.
- A replica may answer checks only at revisions it has fully applied and published.

### Shard

A partition of tenant authorization state.

Initial strategy:

```text
shard by tenant
```

Later strategies for very large tenants may shard by workspace, organization, object namespace, or object ID hash.

### Shard Router

The component that maps a tenant/object key to the shard responsible for it.

Rules:

- Writes must route to the shard leader.
- Reads may route to a follower only if the follower can satisfy the requested consistency mode.

### Placement

The assignment of replicas to servers, hosts, availability zones, or regions.

Placement answers:

```text
Where should each replica live so the shard remains available after failure?
```

### Leader

The replica that accepts writes for a shard in a leadership epoch.

Rules:

- A shard has at most one valid leader per epoch.
- Writes are ordered by the leader before replication.

### Follower

A replica that receives log entries from the leader and applies them to local state.

Rules:

- A follower may serve reads only from its published revision.
- A follower must reject, wait, or redirect reads that require a revision it has not applied.

### Leadership Epoch

A monotonically increasing term identifying a period of shard leadership.

Rules:

- Log entries are associated with an epoch.
- A stale leader must not commit new writes after losing leadership.

### Consensus Log

The replicated form of the WAL.

Rules:

- The consensus log is the source of truth for a replicated shard.
- The same committed log prefix must produce the same schema registry, dictionaries, tuples, indexes, and revisions on every replica.

### Quorum

The minimum set of replicas required to commit a write.

Rules:

- A write is committed only after the replication protocol's quorum rule is satisfied.
- A committed write may not yet be applied on every replica.

### Committed Revision

The highest revision durably accepted by the replication protocol for a shard.

Rules:

- Committed means durable by quorum.
- Committed does not imply queryable on every replica.

### Applied Revision

The highest committed revision a replica has applied to schema, dictionaries, tuples, and indexes.

Rules:

- A replica must apply revisions in log order.
- A replica may not publish a revision until all derived state for that revision is applied.

### Published Revision

The highest applied revision visible to checks on a replica.

Rules:

- Checks evaluate at a published revision.
- A replica may answer a check only at or below its published revision.
- Published revision must never exceed applied revision.

### Revision Token

A client-facing freshness token returned by writes and accepted by reads.

Example:

```text
rev_1050
```

Rules:

- Clients use revision tokens to enforce read-after-grant and read-after-revoke.
- Revision tokens are logical consistency tokens, not wall-clock timestamps.

### Minimum Revision

A client requirement that a read must evaluate at least a specific revision.

Example:

```text
at_least(rev_1050)
```

Rules:

- If a replica has not published the minimum revision, it must wait, redirect, or reject.
- It must not answer from an older revision while claiming freshness.

### Read-After-Write

A guarantee that a client can read the effects of a successful write by requiring at least the write's returned revision.

This is the generic database term. Authorization-facing docs should prefer the more specific terms read-after-grant and read-after-revoke.

### Read-After-Grant

A guarantee that a client can observe newly granted access by requiring at least the grant write's returned revision.

### Read-After-Revoke

A safety-sensitive form of read-after-write where the write removed access.

Rule:

```text
After revocation, checks that require the revocation revision must not be answered by stale replicas.
```

### Stale Read

A read served below the newest committed revision.

Rules:

- Stale reads may be acceptable for some checks only under an explicit consistency mode.
- Stale reads are dangerous after revocation unless bounded by a client-selected freshness requirement.

### Follower Read

A read served by a non-leader replica.

Rules:

- Follower reads can reduce latency and leader load.
- Follower reads are valid only when the follower's published revision satisfies the request.

### Strong Read

A read that must observe a fresh enough revision according to the selected consistency mode.

In practice this may require leader routing, waiting for follower catch-up, or rejecting stale replicas.

### Bounded Staleness

A consistency mode that allows reads behind the latest committed revision by no more than a defined lag.

MVP 1 does not implement bounded staleness.

### Catch-Up

The process of bringing a behind replica closer to the committed revision.

Methods:

- replaying log entries
- installing a snapshot
- applying checkpoint plus log tail

### Snapshot Shipping

Sending checkpointed state to a replica so it can catch up without replaying the full log.

### Failover

The process of replacing a failed leader with a new leader.

Rules:

- Failover must preserve committed log order.
- A new leader must not lose committed authorization history.

### Split Brain

A failure mode where more than one leader accepts writes for the same shard and epoch.

Rule:

```text
Split brain is fatal to authorization correctness and must be prevented by the replication protocol.
```

### Consistency Modes

Possible distributed consistency modes:

```text
latest
at_least(revision)
bounded_staleness(max_lag)
leader_only
```

Rules:

- `at_least(revision)` is the core safety mode for read-after-grant and read-after-revoke.
- `leader_only` may be useful for sensitive checks or operational debugging.
- `bounded_staleness` is an optimization mode, not a substitute for revocation freshness.

---

## 6. Anti-Corruption Language

Veriqik should avoid importing external terminology when it weakens the domain model.

### Preferred Terms

| Prefer | Avoid | Reason |
|---|---|---|
| relation | stored permission | Relations are stored tuple-backed edges. |
| permission | computed relation | Permissions are compiled programs. |
| tuple | policy row | Tuples are relationship facts, not generic policy rows. |
| grant | generic write | Grant names the authorization effect of creating access. |
| revoke | generic delete | Revoke names the authorization effect of removing access. |
| check | query | Check has authorization-specific semantics. |
| eval | public check | Eval is internal only. |
| failed closed | denied | Failed closed means uncertainty, not clean denial. |
| revision | timestamp | Revisions are logical consistency tokens. |
| WAL | event log | WAL is the durable database log, not product analytics. |
| checkpoint | cache | Checkpoints are durable recovery artifacts. |
| committed revision | applied revision | Committed means replicated; applied means queryable locally. |
| revision token | timestamp | Revision tokens are logical freshness tokens. |

### External System Mapping

| External concept | Veriqik term |
|---|---|
| Zanzibar relation tuple | tuple |
| Zanzibar userset | userset |
| OpenFGA relation used as computed access | permission, if computed |
| OpenFGA tuple store | relationship storage, but not the whole database |
| SpiceDB definition | type |
| SpiceDB relation | relation |
| SpiceDB permission | permission |
| SpiceDB caveat | caveat, deferred from MVP 1 |
| policy engine decision | check result |
| consensus log entry | replicated command batch |

---

## 7. Naming Rules

### Public API Names

Use domain terms:

- `write_schema`
- `write_relationships`
- `delete_relationships`
- `check`
- `batch_check`
- `explain_one`
- `health`
- `current_revision`

Do not expose internal names such as `eval` in public client APIs.

### Internal Code Names

Internal code may use:

- `EvalTarget`
- `CheckState`
- `MemoKey`
- `TupleKey`
- `ObjectRelationKey`
- `SubjectKey`
- `SchemaRegistry`
- `CommandCanonicalizer`
- `ShardRouter`
- `ReplicaState`
- `RevisionToken`
- `LeadershipEpoch`

### Debug/Admin Names

Debug/admin commands must be clearly separated from public APIs.

Examples:

- `check_relation_debug`
- `verify_wal`
- `verify_checkpoint`
- `dump_schema_registry`
- `dump_dictionaries`

---

## 8. Invariants in Domain Language

- Writes target relations.
- Checks target permissions.
- Eval may target relations or permissions internally.
- Permissions are compiled programs, not stored edges.
- WAL is the source of truth.
- Indexes are derived and rebuildable.
- Revisions are monotonic.
- Command batches are atomic.
- Authorization uncertainty fails closed.
- Failed closed is distinguishable from denied.
- Schema and dictionary evolution are durable state-machine changes.
- Tenant boundaries are enforced by the data model.
- A replica may answer a check only at a revision it has fully applied and published.
- Committed does not imply queryable on every replica; applied and published do.
- A replica that cannot satisfy a minimum revision must wait, redirect, or reject.
- Read-after-grant and read-after-revoke require checks to evaluate at least the relevant write revision.
- Split brain is fatal to authorization correctness and must be prevented.
