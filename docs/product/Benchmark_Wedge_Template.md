# Veriqik Benchmark Wedge Template

**Tagline:** A purpose-built database for fine-grained authorization.

This document is a working template for the benchmark workload that should validate or weaken the product thesis.

The benchmark wedge should be narrow, repeatable, and falsifiable. It should describe the workload Veriqik must win before the roadmap expands.

## 1. Benchmark Question

Question:
What workload must Veriqik outperform or simplify enough to justify a purpose-built authorization database?

Current hypothesis:
High-volume `check` and `batch_check` workloads over relationship graphs where read-after-grant and read-after-revoke freshness matters.

## 2. Workload Shape

Initial scale target:

- 1,000 orgs
- 10,000 teams
- 100,000 groups
- 1,000,000 users
- 100,000,000 documents

The current prototype exposes this with:

```sh
cd prototype
zig build run -- load-plan
```

Current generated shape:

- nested groups
- org admin inheritance
- org-scoped active membership
- team membership
- folder parent inheritance
- document parent/team/org traversal
- banned exclusions
- multiple viewer edges per resource

Current prototype stance:

The benchmark should not model `active` as a per-document relation to users. At 100,000,000 documents and 1,000,000 users, that creates a document-by-user matrix and overwhelms the authorization graph with an unrealistic relation.

The current load shape models activity at org scope:

```text
org:o1#active_member@user:u1
permission view = allowed & org.active - banned
```

If activity/state constraints are needed later, they should be:

- inherited from team/org/resource scope
- modeled through future caveats/context
- removed from the benchmark and replaced with another high-fanout constraint

Capture:

- tenant count
- subject count
- object/resource count
- relationship count
- relation fanout
- permission expression shape
- read/write ratio
- check concurrency
- batch size
- grant/revoke frequency
- freshness mode
- explain frequency

## 3. Baselines

Compare against:

- OpenFGA
- SpiceDB/Authzed
- any app-owned authorization implementation used as a practical baseline

Each baseline should run with documented configuration, datastore choice, consistency mode, cache settings, and hardware/runtime environment.

## 4. Metrics

Measure:

- p50, p95, and p99 direct check latency
- p50, p95, and p99 batch-check latency
- throughput under concurrent checks
- latency for read-after-grant and read-after-revoke checks
- explain-one latency
- memory usage
- CPU usage
- storage size
- recovery/replay time
- application-owned cache dependence
- tuning effort and operational notes

## 5. Success Thresholds

To be filled after the first benchmark harness exists.

Thresholds should be concrete enough to falsify the product thesis for the chosen workload.

Examples:

- fresh checks after grants and revokes complete within a defined p99 budget
- batch checks with overlapping subproblems beat individual checks by a defined factor
- Veriqik runs the chosen workload without app-owned authorization caching
- recovery from durable state completes within a defined budget

## 6. Interpretation

Benchmark results should update:

- [Thesis.md](Thesis.md)
- [Wedge_Template.md](Wedge_Template.md)
- [Discovery_Backlog.md](Discovery_Backlog.md)
- [../plans/High_Level_Roadmap.md](../plans/High_Level_Roadmap.md)

If Veriqik does not win the chosen workload, the next step should be to revise the product thesis, database design, or benchmark wedge before expanding the roadmap.
