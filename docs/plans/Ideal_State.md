# Veriqik Ideal State Plan

**Tagline:** A purpose-built database for fine-grained authorization.

## 1. Product Vision

Veriqik is a domain-specific authorization database for Fine-Grained Authorization (FGA) and Relationship-Based Access Control (ReBAC).

It combines:

- Durable relationship storage
- Native `relation` and `permission` schema semantics
- Revision-based consistency
- Indexed graph traversal
- Explainable access decisions
- Performance analysis
- Eventually, replicated consensus and distributed scale

---

## 2. Key Differentiator

Veriqik separates tuple-backed relations from computed permissions.

```text
relation viewer: user | group#member
permission view = viewer + editor + parent.view
```

This enables permission-level:

- Planning
- Indexing
- Caching
- Profiling
- Explainability
- Materialization
- Benchmarking

Permissions do not create extra graph hops by default. They compile into execution programs.

---

## 3. High-Level Architecture

```mermaid
flowchart TD
    Client[Client SDK / App] --> API[FGA API / QL Gateway]

    API --> CommandIR[Typed Command IR]
    API --> Parser[Schema + QL Parser]

    Parser --> Compiler[Schema Compiler]
    Compiler --> SchemaStore[Compiled Schema Store]

    CommandIR --> Engine[Authorization State Machine]

    Engine --> Log[WAL / Consensus Log]
    Engine --> Indexes[Materialized Tuple Indexes]
    Engine --> Revision[Revision Manager]
    Engine --> CheckEngine[Check / Explain Engine]

    Log --> Snapshot[Checkpoints / Snapshots]
    SchemaStore --> CheckEngine
    Indexes --> CheckEngine
    Revision --> CheckEngine

    CheckEngine --> Result[Decision / Proof / Stats]
    Result --> Client
```

---

## 4. Roadmap Overview

| Phase | Name | Purpose |
|---:|---|---|
| 0 | MVP 1 | Single-node durable engine |
| 1 | Core Authorization Semantics | Add comparison-critical auth operators |
| 2 | Operational Readiness | Make it safe to operate |
| 3 | Domain-Specific QL | Human-friendly command interface |
| 4 | Performance Analysis and Benchmarking | Compare with existing systems |
| 5 | Performance Optimization | Optimize based on measurements |
| 6 | Replication and Consensus | Fault-tolerant replicated log |
| 7 | Distributed Revisions | Strong read-after-write across replicas |
| 8 | Sharding and Multi-Tenant Scale | Scale beyond one write stream |
| 9 | Extended Authorization Semantics | Caveats, wildcards, context |
| 10 | Materialized Authorization | Selective effective permission indexes |
| 11 | Global Distribution | Multi-region operation |
| 12 | Authorization Platform | UI, graph explorer, simulation, tooling |

---

# Phase 0 – MVP 1

## Goal

Build a correct, durable, single-node authorization database.

## Features

- Single-node state machine
- WAL
- Checkpoints
- Relationship tuples
- Native schema DSL
- Explicit `relation`
- Explicit `permission`
- Exists/forward/reverse indexes
- Permission program compiler
- Check engine
- Batch check
- Explain-one
- Revision consistency
- Basic stats

## Architecture

```mermaid
flowchart LR
    API[API] --> Engine[Single-Node Engine]
    Engine --> WAL[WAL]
    Engine --> Indexes[Base Indexes]
    Engine --> Schema[Compiled Schema]
    Engine --> Check[Check Engine]
```

## Outcome

A usable embedded or standalone authorization database.

---

# Phase 1 – Core Authorization Semantics

## Goal

Support the semantic features needed for meaningful comparison against OpenFGA, SpiceDB/Authzed, and Zanzibar-style systems.

## Features

- Union
- Intersection
- Exclusion/difference
- Recursive group membership
- Nested usersets
- Parent inheritance
- Tenant/org admin inheritance
- Permission dependency graph
- Denial explanation summary
- Multi-branch permission evaluation

## Architecture

```mermaid
flowchart TD
    SchemaText[Schema DSL] --> Parser[Parser]
    Parser --> IR[Permission Expression IR]

    IR --> Relation[Relation Reference]
    IR --> Permission[Permission Reference]
    IR --> Union[Union]
    IR --> Intersection[Intersection]
    IR --> Difference[Difference]
    IR --> Traversal[Traversal: parent.view]

    IR --> Compiler[Permission Program Compiler]
    Compiler --> Program[Executable Permission Program]
```

## Outcome

The engine can run realistic FGA benchmarks.

---

# Phase 2 – Operational Readiness

## Goal

Make the engine safe to run.

## Features

- Structured logs
- Metrics
- Slow-check logging
- Health endpoints
- WAL verifier
- Checkpoint verifier
- Backup/restore
- Storage scrubber
- Admin CLI

## Architecture

```mermaid
flowchart TD
    Engine[Engine] --> Metrics[Metrics]
    Engine --> Logs[Structured Logs]
    Engine --> Health[Health Endpoint]

    WAL[WAL] --> Verifier[WAL Verifier]
    Checkpoints[Checkpoints] --> Backup[Backup / Restore]
    Storage[Storage Files] --> Scrubber[Background Scrubber]
```

## Outcome

The engine can be operated and debugged.

---

# Phase 3 – Domain-Specific QL

## Goal

Add a human-friendly command language while keeping the engine operation surface narrow.

## Example

```text
WRITE RELATIONSHIP group:eng#member@user:kien;
CHECK user:kien CAN view document:doc1;
EXPLAIN user:kien CAN view document:doc1;
```

## Architecture

```mermaid
flowchart TD
    TextQL[Text QL] --> Lexer[Lexer]
    Lexer --> Parser[Parser]
    Parser --> AST[QL AST]
    AST --> Validator[Validator]
    Validator --> CommandIR[Typed Command IR]
    CommandIR --> Engine[State Machine]
```

## Rule

QL compiles to fixed commands. It is not an arbitrary graph query language.

## Outcome

Strong developer experience.

---

# Phase 4 – Performance Analysis and Benchmarking

## Goal

Measure the engine against realistic workloads and existing systems.

## Features

- Per-check stats
- Branch-level traces
- Slow-check samples
- High-fanout detection
- Benchmark runner
- Dataset generators
- Comparison workloads
- Explain cost measurement

## Architecture

```mermaid
flowchart TD
    Workloads[Benchmark Workloads] --> Runner[Benchmark Runner]

    Runner --> Veriqik[Veriqik]
    Runner --> Baselines[Other FGA Systems]

    Veriqik --> Stats[Stats + Traces]
    Baselines --> BaselineMetrics[Baseline Metrics]

    Stats --> Report[Comparison Report]
    BaselineMetrics --> Report
```

## Benchmark Categories

- Direct checks
- Group checks
- Nested groups
- Parent inheritance
- Tenant admin inheritance
- Intersection
- Exclusion
- Denial checks
- Batch checks
- Explain-one
- High-fanout relations

## Outcome

Evidence-based optimization roadmap.

---

# Phase 5 – Performance Optimization

## Goal

Optimize based on measured bottlenecks.

## Features

- Permission plan ordering
- Fanout statistics
- Revision-aware caches
- Bounded global caches
- Selective group closure
- Witness metadata for explain
- Optimized `lookupObjects`
- Optimized `lookupSubjects`

## Architecture

```mermaid
flowchart TD
    Check[Check Request] --> Planner[Permission Planner]
    Planner --> Cache{Cache Hit?}

    Cache -- Yes --> Result[Return Result]
    Cache -- No --> Eval[Evaluate Program]

    Eval --> Memo[Memoization]
    Eval --> Closure[Optional Closure Index]
    Eval --> BaseIndexes[Base Indexes]

    Eval --> StoreCache[Store Cache Entry]
    StoreCache --> Result
```

## Outcome

Lower latency for hot workloads.

---

# Phase 6 – Replication and Consensus

## Goal

Make Veriqik fault-tolerant.

## Architecture

```mermaid
flowchart TD
    Client[Client] --> Leader[Shard Leader]

    Leader --> F1[Follower 1]
    Leader --> F2[Follower 2]

    Leader --> LogA[Leader Log]
    F1 --> LogB[Follower Log]
    F2 --> LogC[Follower Log]

    LogA --> ApplyA[Apply Indexes]
    LogB --> ApplyB[Apply Indexes]
    LogC --> ApplyC[Apply Indexes]
```

## Write Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant L as Leader
    participant F1 as Follower 1
    participant F2 as Follower 2

    C->>L: Write batch
    L->>L: Append rev=1050
    L->>F1: Replicate rev=1050
    L->>F2: Replicate rev=1050
    F1-->>L: Ack
    L-->>C: Committed rev=1050
    F2-->>L: Ack later
```

## Outcome

Durable replicated authorization history.

---

# Phase 7 – Distributed Revisions

## Goal

Support read-after-write and read-after-revoke in replicated systems.

## Concepts

- committed revision
- applied revision
- min revision
- revision tokens
- follower reads

## Architecture

```mermaid
flowchart TD
    Req["Check min_revision=1050"] --> Router[Read Router]

    Router --> R1["Replica A applied=1052"]
    Router --> R2["Replica B applied=1048"]
    Router --> R3["Replica C applied=1050"]

    R1 --> OK1[Can Answer]
    R2 --> Wait[Wait or Reject]
    R3 --> OK2[Can Answer]
```

## Outcome

Clients can enforce freshness requirements.

---

# Phase 8 – Sharding and Multi-Tenant Scale

## Goal

Scale beyond one write stream.

## Initial Strategy

Shard by tenant.

```mermaid
flowchart TD
    Router[Tenant Router]

    Router --> S1["Shard 1<br/>Tenants A-F"]
    Router --> S2["Shard 2<br/>Tenants G-M"]
    Router --> S3["Shard 3<br/>Tenants N-Z"]

    S1 --> L1[Leader 1]
    S2 --> L2[Leader 2]
    S3 --> L3[Leader 3]
```

## Later Strategy

For very large tenants, shard by:

- Workspace
- Organization
- Object namespace
- Object ID hash

## Outcome

More write and storage scale.

---

# Phase 9 – Extended Authorization Semantics

## Goal

Add specialized semantics after baseline performance is understood.

## Features

- Wildcards
- Caveats
- Contextual conditions
- Time-bound relationships
- Attribute checks
- Schema migration validation

## Architecture

```mermaid
flowchart TD
    Schema[Schema DSL] --> Compiler[Compiler]
    Compiler --> Program[Permission Program]

    Context[Request Context] --> Evaluator[Advanced Evaluator]
    Program --> Evaluator
    Indexes[Tuple Indexes] --> Evaluator

    Evaluator --> Decision[Decision]
```

## Outcome

Richer enterprise authorization models.

---

# Phase 10 – Materialized Authorization

## Goal

Make selected hot permissions extremely fast.

## Features

- Effective permission indexes
- Incremental recomputation
- Dependency tracking
- Revocation-safe invalidation
- Witness metadata for explain

## Architecture

```mermaid
flowchart TD
    TupleWrite[Tuple Write/Delete] --> BaseIndexes[Base Indexes]
    TupleWrite --> DependencyGraph[Dependency Graph]

    DependencyGraph --> Recompute[Incremental Recompute]
    Recompute --> EffectiveIndex[Effective Permission Index]

    Check[Check Request] --> EffectiveIndex
    EffectiveIndex --> Decision[Fast Decision]
    EffectiveIndex --> Witness[Proof Witness]
```

## Warning

Naive materialization can explode:

```text
users × objects × permissions
```

## Outcome

Sub-millisecond checks for selected hot paths.

---

# Phase 11 – Global Distribution

## Goal

Support multi-region operation.

## Features

- Regional replicas
- Geo-aware routing
- Disaster recovery
- Snapshot shipping
- Region failover
- Bounded-staleness modes
- Strong-region mode for sensitive checks

## Architecture

```mermaid
flowchart TD
    RegionA[Region A Primary] --> RegionB[Region B Replica]
    RegionA --> RegionC[Region C Replica]

    ClientA[Client in Region A] --> RegionA
    ClientB[Client in Region B] --> RegionB
    ClientC[Client in Region C] --> RegionC
```

## Outcome

Enterprise-grade availability and disaster recovery.

---

# Phase 12 – Authorization Platform

## Goal

Turn Veriqik into a complete authorization platform.

## Features

- Visual graph explorer
- Explain UI
- Schema migration assistant
- Performance analyzer
- Access simulation
- Audit viewer
- Policy testing
- Workload replay
- IDE support
- SDKs

## Architecture

```mermaid
flowchart TD
    Core[Core FGA DB] --> AdminAPI[Admin API]

    AdminAPI --> UI[Web Console]
    AdminAPI --> CLI[CLI]
    AdminAPI --> SDKs[SDKs]

    UI --> Graph[Graph Explorer]
    UI --> Explain[Explain Viewer]
    UI --> Perf[Performance Analyzer]
    UI --> Audit[Audit Viewer]
    UI --> Migration[Migration Assistant]
```

## Outcome

A complete authorization platform.

---

# Revised Build Order

```mermaid
gantt
    title Veriqik Revised Roadmap
    dateFormat  YYYY-MM-DD

    section Foundation
    MVP 1 Single Node                 :a1, 2026-01-01, 90d
    Core Authorization Semantics      :a2, after a1, 60d
    Operational Readiness             :a3, after a2, 45d
    QL + CLI                          :a4, after a3, 45d

    section Measurement
    Performance Analysis + Benchmarks :b1, after a4, 60d
    Optimization Layer                :b2, after b1, 75d

    section Distributed
    Replication + Consensus           :c1, after b2, 120d
    Distributed Revisions             :c2, after c1, 60d
    Sharding                          :c3, after c2, 90d

    section Advanced
    Extended Authorization Semantics  :d1, after c3, 90d
    Materialized Authorization        :d2, after d1, 90d
    Global Distribution               :d3, after d2, 120d
    Platform Features                 :d4, after d3, 120d
```

---

# Design Principles

1. Correctness before speed
2. WAL/consensus log is the source of truth
3. Indexes are derived and rebuildable
4. Relations are stored; permissions are compiled
5. Checks target permissions
6. Writes target relations
7. Revisions are part of the API
8. Fail closed when authorization state is uncertain
9. Batch first
10. Explainability is a product feature
11. Keep the operation surface small
12. Implement comparison-critical semantics before serious benchmarking
