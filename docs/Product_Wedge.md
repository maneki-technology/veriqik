# Veriqik Product Wedge Template

**Tagline:** A purpose-built database for fine-grained authorization.

This document is a working template for turning the product thesis into a narrower product strategy. The thesis explains why Veriqik should exist. This template captures hypotheses about where Veriqik could win first, who could care first, and what could make the product fail.

Nothing in this document is final positioning. Treat each section as a prompt to refine, validate, replace, or delete.

## 1. First Customer

Hypothesis: Veriqik's first customer is an infrastructure or platform team that owns authorization as shared product infrastructure.

This team likely has:

- many tenants, workspaces, projects, documents, repositories, records, or resources
- many relationship edges between users, groups, roles, organizations, and resources
- latency-sensitive authorization checks on critical request paths
- safety-sensitive grant and revoke behavior
- a need to explain authorization decisions to engineers, operators, auditors, or customers
- a desire to avoid spreading authorization logic across application services and storage queries

The first customer may not be looking for a general policy engine. They may be looking for authorization storage, authorization checks, consistency, recovery, and explainability in one system.

Possible beachhead: regulated, high-value action authorization, where FGA decides whether a subject may perform sensitive operations, and which resource scopes, attributes, or constraints are allowed.

## 2. First Pain

Hypothesis: the first pain is not "we need authorization." Many systems can provide authorization.

The first pain may be:

> Our authorization graph has become important enough that correctness, freshness, latency, recovery, and explainability need to be owned by one purpose-built database.

Possible symptoms:

- authorization logic is duplicated across services
- permission checks require several datastore reads or service calls
- revocation freshness is hard to prove
- denial debugging is slow or ambiguous
- relationship data is stored in a general database but queried like an authorization graph
- batch authorization is expensive
- production behavior depends on datastore-specific query plans or cache behavior
- the application adds Redis or another app-level cache in front of FGA because the authorization API workload is too high
- strong-consistency read-after-grant or read-after-revoke requests become slow or hard to tune under concurrency

## 3. First Winning Workload

Hypothesis: Veriqik should win first on high-volume `check` and `batch_check` workloads over relationship graphs where freshness matters.

Possible canonical workload:

```text
Can subject S perform action A on resource R under constraint C at revision V?
```

The initial workload could include:

- direct subject-to-object relationships
- group membership
- nested groups
- parent/resource inheritance
- tenant or organization admin inheritance
- revision-aware read-after-grant and read-after-revoke
- concurrent read-after-grant and read-after-revoke checks after relationship updates
- proof paths for successful checks
- failed-closed results when authorization state is uncertain
- request-local and batch-local memoization

This is narrow enough to implement and benchmark, but broad enough to represent real FGA usage.

## 4. Why Veriqik Should Win

Hypothesis: Veriqik should win because it treats the authorization workload as a database workload.

The product advantage may come from:

- compiled permission programs instead of ad hoc application logic
- native authorization indexes instead of generic query plans
- no internal FGA-to-DB network hop during check/eval
- deterministic state-machine execution
- WAL-backed recovery and derived indexes
- revision tokens as part of the API
- bounded traversal and explicit failure modes
- proof paths and stats as database outputs
- performance tuning as a database-native concern, not a cache layer pushed into every application

The product should not rely on vague claims that it is "faster" or "simpler." This template should eventually name where the database-native design creates measurable advantages.

## 5. Switching Trigger

A team may consider Veriqik when one or more of these are true:

- authorization checks are on a latency-sensitive path
- authorization data is large enough that indexes and traversal behavior matter
- revocation freshness must be explicit and testable
- debugging access decisions consumes engineering time
- the team wants a durable authorization database, not only a service layer over another datastore
- app-owned authorization logic has become a correctness risk
- batch checks are common and expensive
- the application already needs a cache in front of FGA to survive normal API load
- strong-consistency reads after grants or revokes are too slow for product workflows

Hypothesis: Veriqik does not need to be the right answer for every FGA user. It needs to be the obvious answer for teams whose authorization graph behaves like a critical database workload.

## 6. Adoption Path

Possible first adoption path:

1. Embedded engine and tests for schema, tuple, check, batch check, explain, and recovery behavior.
2. CLI for local usage, fixtures, demos, and repeatable benchmark workloads.
3. Network API before comparative load and stress testing against OpenFGA, SpiceDB/Authzed, and other systems.
4. SDKs and operational tooling after the core engine has proven correctness and performance.

The DSL is intentionally Veriqik-native. Migration support may focus first on concepts, tuple import/export, workload generation, and schema translation guides rather than full syntax compatibility.

## 7. Explicit Non-Goals

Possible early non-goals:

- a general graph database
- a general policy engine
- an IAM product or user directory
- an OPA replacement
- a hosted authorization SaaS
- a full SpiceDB-compatible server
- a full OpenFGA-compatible server
- an enterprise authorization platform with UI, audit workflows, and simulation from day one

These boundaries are placeholders. They should be revisited as the first customer and workload become clearer.

## 8. Product Proof Points

The product thesis may be considered stronger when Veriqik can demonstrate:

- correct direct, group, nested group, and parent-inheritance checks
- durable relationship writes and deterministic recovery
- explicit read-after-grant and read-after-revoke behavior
- concurrent read-after-grant and read-after-revoke checks that complete predictably under strong freshness requirements
- failed-closed behavior distinguishable from denial
- useful proof output for successful checks
- useful stats for expensive checks
- competitive or better check latency on the first winning workload
- competitive or better batch-check behavior when subproblems overlap
- lower dependence on application-owned caching for the first winning workload
- repeatable benchmarks against existing FGA systems

Until then, performance and operational advantages remain hypotheses.

## 9. Failure Modes

Veriqik can fail even if the implementation is technically interesting.

The major product failure modes are:

- no sharply defined customer
- no workload where the database-native design clearly wins
- no measurable performance advantage over mature FGA systems
- correctness bugs that damage trust
- operational burden that exceeds the value of specialization
- delayed support for authorization semantics that real users need
- weak migration or adoption path
- unclear category positioning
- too much roadmap before the first wedge is proven

The product should avoid proving infrastructure for its own sake. Every major phase should make the first customer more confident that Veriqik is a better authorization database for their critical workload.
