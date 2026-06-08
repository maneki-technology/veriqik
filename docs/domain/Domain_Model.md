# Veriqik Domain Model

This document describes Veriqik's DDD model: entities, value objects, aggregates, consistency boundaries, and domain services.

Start with [Domain_Language.md](Domain_Language.md) for the vocabulary. This document uses that language to describe ownership and modeling boundaries.

---

## 1. DDD Classification

### Entities

Entities have identity and lifecycle.

- Tenant
- Schema Version
- Tuple
- Command Batch
- WAL Record
- Checkpoint
- Server
- Replica
- Shard
- Leadership Epoch

### Value Objects

Value objects are immutable, comparable by value, and safe to use as keys.

- Type ID
- Object ID
- Relation ID
- Permission ID
- Subject Key
- Object Relation Key
- Tuple Key
- Eval Target
- Revision
- Revision Token
- Request ID
- Check Limits

### Aggregates

Aggregates define consistency boundaries.

### Tenant Authorization State

Root:

```text
Tenant
```

Contains:

- active schema version
- dictionaries
- tuples
- indexes
- current revision
- future idempotency table

Consistency rules:

- no cross-tenant tuples
- tuple validates against active schema
- indexes reflect tuple state
- revisions are monotonic

### Schema Registry

Root:

```text
Schema Version
```

Contains:

- compiled type definitions
- relation definitions
- permission programs
- tombstoned names

Consistency rules:

- relation and permission names do not collide within a type
- traversals resolve
- permission expressions compile
- schema changes preserve existing tuple validity

### Storage Log

Root:

```text
WAL
```

Contains:

- ordered WAL records
- future checkpoint boundary
- segment metadata

Consistency rules:

- revisions are contiguous
- checksums verify
- record order is deterministic
- future checkpoint revision is a prefix of applied WAL state

### Replicated Shard

Root:

```text
Shard
```

Contains:

- replicas
- leader
- leadership epoch
- consensus log
- committed revision
- placement metadata

Consistency rules:

- one leader per shard epoch
- committed revisions are ordered and durable by quorum
- replicas apply committed revisions in order
- published revision never exceeds applied revision
- checks are served only from published revisions

### Replica State

Root:

```text
Replica
```

Contains:

- committed revision known to the replica
- applied revision
- published revision
- local schema registry
- local dictionaries
- local indexes
- catch-up state

Consistency rules:

- applied revision never exceeds committed revision known to the replica
- published revision never exceeds applied revision
- a replica may answer `at_least(N)` only when `published_revision >= N`

### Domain Services

Domain services implement behavior that does not naturally belong to one entity.

- Schema Compiler
- Schema Compatibility Validator
- Command Canonicalizer
- Relationship Writer
- Relationship Deleter
- Check Evaluator
- Batch Check Evaluator
- Explain-One Builder
- Recovery Service
- Checkpoint Writer
- WAL Verifier
- Replication Service
- Leader Election Service
- Shard Router
- Catch-Up Service
- Snapshot Shipping Service
