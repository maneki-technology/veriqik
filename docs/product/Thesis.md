# Veriqik Product Thesis

**Tagline:** A purpose-built database for fine-grained authorization.

Veriqik is a domain-specific database for Fine-Grained Authorization (FGA) and Relationship-Based Access Control (ReBAC).

The thesis is simple: authorization logic, relationship storage, indexes, revisions, recovery, and check execution should be designed together as one database system.

For draft hypotheses about the first customer, first winning workload, adoption path, and product failure modes, see [Wedge_Template.md](Wedge_Template.md).

## 1. The Product Bet

Existing FGA systems prove that relationship-based authorization is useful and important. Veriqik accepts that direction and competes by making a stronger database claim.

Fine-grained authorization should not be treated as only a service layer over a general datastore abstraction. The database itself should understand authorization semantics.

Fine-grained authorization is common enough, latency-sensitive enough, and correctness-sensitive enough to justify a database built specifically for it. Modern applications repeatedly need the same authorization shape: subjects, objects, relationships, permissions, revocation freshness, auditability, and explainability. Veriqik treats that as a database workload, not incidental application logic.

This matters most when authorization sits on critical product paths, such as regulated action authorization, where every sensitive operation may require fresh permission checks.

This is the same kind of product bet TigerBeetle makes for online transaction processing: when a domain is common, safety-critical, and performance-sensitive, a narrow database with domain-native primitives can be better than forcing the workload through a general-purpose database model.

Veriqik should be better when these concerns are designed together:

- stored relationships
- compiled permission programs
- native authorization indexes
- revision-aware checks
- read-after-grant and read-after-revoke
- failed-closed behavior
- explainability and profiling
- recovery from durable state
- future replication and distributed freshness

## 2. TigerBeetle Analogy

TigerBeetle exists because online transaction processing is common and important enough to deserve a purpose-built database. It does not try to be a general-purpose database; it specializes around transaction processing, durable correctness, batching, predictable latency, and domain-native primitives.

Veriqik makes the analogous bet for fine-grained authorization.

The analogy is about product shape, not identical semantics:

- TigerBeetle specializes around accounts, transfers, debits, credits, and transaction processing.
- Veriqik specializes around relationships, permissions, checks, revisions, explanations, and authorization freshness.
- Both bets prefer a narrow, domain-specific database boundary over a generic data model plus application logic.

In transaction processing, the market has both service/platform-style ledger systems and database-native systems such as TigerBeetle. In FGA, OpenFGA and SpiceDB represent the mature service-oriented category. Veriqik is exploring the database-native category.

## 3. What Veriqik Competes Against

Veriqik competes with:

- existing FGA systems such as OpenFGA and SpiceDB
- authorization services layered over PostgreSQL, MySQL, document databases, or graph databases
- application-owned authorization logic spread across services and storage queries

These systems can be mature, useful, and operationally attractive. Veriqik is not claiming they are invalid. Veriqik is making a different product bet: a purpose-built authorization database can provide a better foundation for correctness, freshness, explainability, and performance.

## 4. Core Differentiator

Veriqik's differentiator is database design.

The system should have:

- a narrow command surface
- deterministic state-machine execution
- WAL as the durable source of truth
- derived authorization indexes rebuilt from durable state
- bounded check/eval work
- no internal FGA-to-DB network hop
- revision-first consistency
- failed-closed results distinct from denial
- proof paths and stats as database outputs

The relation/permission split is important, but it is not the main differentiator by itself. SpiceDB/Zed already validates that direction. Veriqik's distinction is that schemas, storage, indexes, revisions, recovery, and evaluation are one database boundary.

## 5. Design Consequences

Veriqik should prefer:

- native authorization indexes over generic query plans
- local check/eval over internal service calls
- deterministic replay over ad hoc state repair
- explicit revisions over wall-clock freshness claims
- explainable failed-closed behavior over ambiguous errors
- benchmarkable hot paths over generic datastore flexibility

These choices increase implementation cost. That cost is intentional if it produces a stronger authorization database.

## 6. What Must Be Proven

The thesis is not proven by documentation. It must be proven by implementation and benchmarks.

Veriqik must show:

- correct direct and indirect permission checks
- durable writes and deterministic recovery
- predictable read-after-grant and read-after-revoke behavior
- clear failed-closed behavior under uncertainty
- useful explanation output
- competitive check and batch-check performance
- operational behavior that can eventually support production use

Until those are measured, performance and operational advantages are hypotheses.
