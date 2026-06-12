# Prototype Lessons Learned

Status: Draft  
Scope: Lessons from the in-memory Zig prototype and generated load tests.

This document records what the prototype has taught us so far. It is not a final architecture decision. Use it as evidence for the product thesis, benchmark plan, MVP scope, and future ADRs.

## 1. Public API Boundary Matters

The load test originally drifted toward internal numeric checks. That made the engine look faster, but it did not represent the public `check(subject, object, permission)` boundary.

Lesson: benchmarks should measure from the public endpoint point of view unless explicitly labeled as an internal engine microbenchmark.

Current stance:

- Public check requests are string-facing.
- The engine decodes public strings into numeric IDs internally.
- Internal numeric execution is valid after the public boundary.
- Benchmark output must state which boundary is being measured.

## 2. Correctness Must Move With Performance

The first large load runs were not useful because nearly all checks were denied. That mostly measured fast denial behavior, not realistic authorization.

Lesson: load data must intentionally include allowed, denied, and revoke/exclusion paths.

Current load shape intentionally includes:

- allowed checks through active direct viewer paths
- allowed checks through document viewer group paths
- allowed checks through parent/folder traversal
- allowed checks through team traversal
- allowed checks through org-admin traversal
- denied checks through missing membership or inactive users
- denied checks through `banned` exclusion
- graph edges for multi-step traversal through document, folder, team, org, and group relationships

Correctness now has fixture-backed tests for operators, traversal, usersets, cycles, and delete/read-after-revoke behavior.

## 3. Numeric Core Is Necessary

String tuple storage was too memory-heavy and not representative of a database core. Numeric tuple storage made the prototype usable at tens of millions of tuples.

Lesson: the core engine should use compact numeric IDs for tuples, indexes, and evaluator keys. Strings belong at API, schema, dictionary, and diagnostic boundaries.

This does not remove the need for durable dictionaries. It means string handling should not dominate the hot authorization path.

The current prototype uses per-type `u32` encoded object IDs. That keeps tuples and indexes compact, but it also creates a real boundary: each object type's encoded ID dictionary can hold at most about 4.29 billion distinct values. `user:1`, `group:1`, and `document:1` can all encode to local ID `1` in separate type-scoped ID spaces, while tuple keys still include the object type.

In Zig, this ID width can be a compile-time storage profile instead of a fixed product-wide constant. A compact profile can use `u32` encoded object IDs for cache density and lower memory use. A large profile can use `u64` object IDs when the deployment needs a wider local ID space. A per-type or per-namespace `u32` profile may preserve compact storage while giving each type or namespace its own encoded ID range.

Lesson: production must make encoded object ID width and ID-space scoping explicit. The API can still expose global string IDs, but the storage engine should choose a compile-time profile such as shard-local `u32`, per-type/per-namespace `u32`, or wider `u64`. The prototype is now testing the per-type `u32` profile.

## 4. Index Shape Dominates Memory

The largest memory wins came from changing index shape, not from small field-level optimizations.

Observed improvements:

- replacing per-bucket `ArrayList` indexes with compact range indexes
- splitting userset edges from direct edges
- indexing only direct relations that are actually traversed
- storing singleton traversal relations in dense arrays
- avoiding the generated-load global tuple hash map

Lesson: Veriqik's advantage depends on domain-specific index layouts. A generic tuple index is simple but quickly becomes wasteful.

## 5. One Index Is Not Enough

Authorization evaluation uses different access patterns:

- exact tuple membership
- userset expansion
- traversal from one object to another
- exclusion checks
- active membership checks

Trying to use one index shape for all of these creates high bucket counts and unnecessary scans.

Lesson: the engine should evolve toward relation-specific and permission-aware indexes, not only generic tuple lookup.

## 6. Dense Indexes Are Promising For Single-Edge Relations

Relations such as document parent, document org, document team, folder parent, and folder team often have at most one target per object.

Lesson: singleton relation shapes should not consume hash buckets per object. Dense object-id arrays are a better fit when the object ID space is compact.

Open question: production data may be sparse or tenant-scoped. Dense indexes should be chosen by relation shape, cardinality, and ID allocation strategy, not blindly applied everywhere.

## 7. The Global Tuple Hash Map Is Expensive

The mutable public-write path still uses a tuple hash map for duplicate detection and delete support. Generated bulk load can avoid it by sorting tuple values and using binary search for exact lookup.

Lesson: tuple identity and mutation support need a deliberate storage design. Keeping a full global tuple hash map forever may be too expensive at large scale.

Future options:

- append-only immutable segments with sorted tuple lookup
- write buffer plus compact read segments
- relation-specific exact indexes
- log-structured tuple storage with compaction

## 8. Memoization Helps, But Needs Visibility

Per-worker memoization improves repeated subproblem evaluation without locks. The current memo footprint appears small in sampled runs, but it uses `smp_allocator`, not the metered load allocator.

Lesson: memoization should remain lock-free or partitioned by worker/shard unless evidence shows cross-worker sharing is worth the coordination cost.

Current metrics now report:

- memo entries
- max entries per worker
- estimated memo bytes
- memo hit rate

## 9. Load Progress And Readable Output Are Productive

Large generated loads can appear stuck without progress output. Raw machine-readable metrics are useful, but humans need readable summaries.

Lesson: benchmark tooling is part of the product. It must report progress, refusal reasons, memory estimates, measured memory, index sizes, memo sizes, latency, throughput, and graph work.

## 10. Estimation Must Be Recalibrated Often

Memory estimates were wrong after each major representation change. That is expected while the storage model is still moving.

Lesson: `load-plan` is a sizing guard, not truth. Measured load output is authoritative. The estimator must be updated whenever tuple, index, dictionary, or check-item representation changes.

## 11. Single-Threaded Load Is A Remaining Bottleneck

Check execution is parallel. Userset forward-index construction for generated load data is now parallelized. Tuple generation/loading and dense/direct index construction are still single-threaded.

Lesson: memory layout was the right first bottleneck to attack. Once the layout stabilizes, parallel tuple generation and broader parallel index construction become the next obvious build-phase optimizations.

## 12. Product Bet Still Needs External Baselines

The prototype shows that a domain-specific FGA database can exploit ReBAC/FGA shape directly. It does not yet prove Veriqik is better than OpenFGA, SpiceDB, or application-level caches.

Lesson: the next benchmark must compare against external systems on the same public-check workload, consistency setting, data shape, and read-after-grant/read-after-revoke expectations.

## Current Technical Direction

Based on this prototype, promising directions are:

- keep public `check` simple and stable
- keep core tuple/eval data numeric
- keep benchmark output explicit about boundary and execution model
- invest in relation-specific indexes
- avoid global mutable structures on the hot read path where possible
- prefer lock-free or partitioned memoization over global shared memo state
- keep correctness fixtures close to DSL and check-engine behavior

## Risks Still Open

- Durable storage may change the best in-memory layout.
- Sparse real-world object ID spaces may weaken dense-array assumptions.
- Real schemas may have higher fanout or different relation cardinalities than the generated load.
- Public network overhead has not been measured yet.
- External product comparisons have not been run.
- Caveats, conditions, and wildcards are not implemented.
