# Veriqik Product Discovery Backlog

**Tagline:** A purpose-built database for fine-grained authorization.

This document tracks unanswered product questions, product risks, and evidence needed to strengthen or reject Veriqik's product thesis.

The backlog is not a decision log. Use ADRs for architectural decisions. Use this document for product questions that need implementation evidence, benchmark evidence, customer evidence, or sharper positioning.

## Status Values

- `Open`: unanswered.
- `In Progress`: currently being investigated.
- `Answered`: enough evidence exists to update the thesis, wedge, roadmap, or spec.
- `Rejected`: the hypothesis is no longer useful.

## P001: First Winning Workload

Status: Open

Question:
Which workload should Veriqik prove first?

Current hypothesis:
High-volume `check` and `batch_check` over relationship graphs where read-after-grant and read-after-revoke freshness matters.

Why it matters:
Without a sharp workload, performance claims are not falsifiable.

How we learn:
Build MVP 1, create a repeatable benchmark dataset, and compare against OpenFGA and SpiceDB/Authzed.

Evidence needed:

- p50, p95, and p99 check latency
- concurrent fresh-check behavior after grants and revokes
- batch-check performance when subproblems overlap
- explain output usefulness
- operational complexity notes

Linked docs:

- [Wedge_Template.md](Wedge_Template.md)
- [Benchmark_Wedge_Template.md](Benchmark_Wedge_Template.md)
- [../plans/MVP1.md](../plans/MVP1.md)
- [../specs/mvp1/Technical_Spec.md](../specs/mvp1/Technical_Spec.md)

## P002: First Customer

Status: Open

Question:
Who is the first customer or daily user?

Current hypothesis:
An infrastructure or platform team that owns authorization as shared product infrastructure.

Why it matters:
The first customer determines packaging, APIs, docs, debugging workflows, migration tooling, and benchmark credibility.

How we learn:
Use MVP 1 to test whether platform engineers can model, load, check, explain, and benchmark realistic authorization workloads.

Evidence needed:

- who writes schemas
- who owns relationship data
- who debugs failed or slow checks
- who cares about read-after-grant and read-after-revoke guarantees
- what integration path feels credible

Linked docs:

- [Wedge_Template.md](Wedge_Template.md)

## P003: Performance Advantage

Status: Open

Question:
Does database-native FGA create a meaningful performance advantage over mature FGA systems?

Current hypothesis:
Veriqik can reduce latency and operational tuning burden by owning storage, indexes, revisions, recovery, and check execution inside one database boundary.

Why it matters:
If Veriqik does not show a meaningful performance or operational advantage, the product thesis weakens.

How we learn:
Implement MVP 1, add a network API before comparative load testing, and benchmark against OpenFGA and SpiceDB/Authzed using the same workload shape.

Evidence needed:

- direct check latency
- batch-check latency
- strong-freshness read latency after grants and revokes
- throughput under concurrent checks
- cache dependence at the application layer
- resource usage and tuning effort

Linked docs:

- [Thesis.md](Thesis.md)
- [Benchmark_Wedge_Template.md](Benchmark_Wedge_Template.md)
- [../plans/High_Level_Roadmap.md](../plans/High_Level_Roadmap.md)

## P004: Adoption And Migration Path

Status: Open

Question:
How can teams evaluate or adopt Veriqik without full OpenFGA or SpiceDB compatibility?

Current hypothesis:
Veriqik should avoid DSL compatibility as a product promise, but still provide concept mapping, tuple import/export, workload generation, and side-by-side check comparison tools.

Why it matters:
Even when the DSL is intentionally Veriqik-native, users need a credible path to compare, migrate, or model existing authorization systems.

How we learn:
Build MVP 1 tooling around schemas, tuples, check fixtures, explain output, and benchmark workloads.

Evidence needed:

- tuple import format
- schema translation examples
- side-by-side check comparison harness
- migration guide for common ReBAC patterns
- clear non-compatibility language

Linked docs:

- [Wedge_Template.md](Wedge_Template.md)
- [../adrs/0002-use-zed-inspired-veriqik-dsl.md](../adrs/0002-use-zed-inspired-veriqik-dsl.md)

## P005: Minimum Viable Semantics

Status: Open

Question:
Which authorization semantics are required before Veriqik can model realistic workloads?

Current hypothesis:
MVP 1 should prove direct checks, group checks, nested groups, parent inheritance, tenant/admin inheritance, revision consistency, and explain-one. Caveats, wildcards, lookup APIs, and materialization can wait.

Why it matters:
If MVP 1 excludes too many semantics, the benchmark may be unrealistic. If it includes too many, the core database thesis may take too long to test.

How we learn:
Build the MVP 1 feature set and validate it against benchmark fixtures and modeled customer-like scenarios.

Evidence needed:

- workloads that fail because of missing semantics
- complexity added by each semantic feature
- benchmark relevance before and after each feature
- explainability impact

Linked docs:

- [../plans/MVP1.md](../plans/MVP1.md)
- [../plans/High_Level_Roadmap.md](../plans/High_Level_Roadmap.md)
- [../adrs/0007-defer-caveats-and-conditional-permissions.md](../adrs/0007-defer-caveats-and-conditional-permissions.md)

## P006: Operational Trust

Status: Open

Question:
What operational behaviors must exist before teams trust Veriqik on critical authorization paths?

Current hypothesis:
Teams need clear recovery behavior, failed-closed semantics, health states, replay guarantees, and eventually backup/restore, checkpoints, verification, and observability.

Why it matters:
Authorization systems fail product trust if operators cannot understand freshness, denial, uncertainty, corruption, recovery, or slow checks.

How we learn:
Use MVP 1 to prove WAL recovery, explicit health states, failed-closed behavior, and explain/stats output. Use later roadmap phases to prove operational readiness.

Evidence needed:

- recovery tests
- corruption/truncated-tail behavior
- health state transitions
- failed-closed examples
- slow-check stats
- operator-facing debugging flow

Linked docs:

- [../plans/MVP1.md](../plans/MVP1.md)
- [../plans/High_Level_Roadmap.md](../plans/High_Level_Roadmap.md)

## P007: Product Category

Status: Open

Question:
How should Veriqik describe its category in one sentence?

Current hypothesis:
Veriqik is an authorization database for teams whose FGA workload is too hot, too correctness-sensitive, or too hard to debug as a service layer over another datastore.

Why it matters:
If users cannot tell whether Veriqik is a library, database, service, policy engine, graph database, or SpiceDB alternative, adoption will be slow.

How we learn:
Refine the message after MVP 1 proves what is actually distinctive.

Evidence needed:

- benchmark results
- integration model
- strongest user pain
- clearest comparison point
- rejected category labels

Linked docs:

- [Thesis.md](Thesis.md)
- [Wedge_Template.md](Wedge_Template.md)
