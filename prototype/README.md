# Veriqik

A purpose-built database prototype for fine-grained authorization.

This directory contains an early Zig prototype for MVP 1 semantics.

The code here is exploratory and is not intended to become the production implementation. It exists to test the DSL, check engine semantics, indexing ideas, memory shape, and benchmark workload.

## Prototype Status

Implemented:

- Veriqik-native schema DSL subset
- `relation` vs `permission` distinction
- union permissions with `+`
- intersection permissions with `&`
- exclusion/difference permissions with `-`
- traversal such as `parent.view`
- tuple writes and deletes
- userset subjects such as `group:eng#member`
- public `check(subject, object, permission)`
- `explain_one` proof path for allowed checks
- batch-check summary execution
- numeric tuple storage in the core engine
- per-type `u32` object ID spaces
- compact split forward indexes for direct object edges and userset edges
- parallel userset forward-index construction for generated load data
- sorted tuple lookup for generated load data instead of a global tuple hash map
- dense single-edge traversal indexes for relation-specific parent/team/org style edges
- public string-facing load checks that decode into the internal numeric evaluator
- per-worker batch memoization for load checks
- parallel load-test check execution
- measured load-test memory, CPU, latency, and throughput output
- revision counter for schema and relationship changes
- traversal limits, cycle fail-closed behavior, and basic stats
- CLI demo
- deterministic local load-test command
- separated schema and tuple fixtures
- unit tests

Not implemented yet:

- durable WAL and replay
- durable numeric dictionaries
- canonical command encoding
- reverse indexes and optimized index structures
- shared memoization across batch-check items
- health state machine
- production network API
- caveats and wildcards

The public API remains string-facing, but the engine resolves tuple writes into in-memory numeric dictionaries and stores compact numeric tuple keys. Object IDs are currently encoded as per-type `u32` values, so each object type has its own compact local ID space. The next implementation step should be durable WAL/replay plus durable dictionaries/indexes, because recovery is part of the MVP 1 proof.

## Run

```sh
zig build test
zig build run -- demo
zig build run -- load
zig build run -- load 2 10 10 50 50 1000
zig build run-fast -- load 10 100 1000 10000 100000 10
zig build run -- load-plan
```

Expected demo shape:

```text
before_delete decision=allowed revision=3 proof=...
after_delete decision=denied revision=4
```

Default load-test shape:

```text
orgs=2 teams=10 groups=10 users=50 documents=50 checks=1000
```

The load shape includes nested groups, org admin inheritance, org-scoped active membership, team membership, folder parent inheritance, document parent/team/org traversal, banned exclusions, direct active document viewers, and multiple viewer edges per resource.

Folders scale with document count and use a bounded parent tree instead of one long chain. That keeps the load test focused on normal multi-step and fanout checks instead of accidentally benchmarking depth-limit failures.

The current load test uses the same core numeric tuple engine as correctness tests. Generated load data uses per-type `u32` object ID spaces, sorted tuple lookup instead of a global tuple hash map, compact userset forward indexes, and dense single-edge traversal indexes for parent/team/org-style relations. Generated load checks enter through the public string-facing `check` boundary, then decode into the internal numeric evaluator and use per-worker memoization after decode. It still exposes missing production pieces such as reverse indexes, materialized permission indexes, cross-worker shared batch memoization, and production-grade write concurrency.

The `load-plan` command estimates the large target workload:

```text
orgs=1000 teams=100000 groups=100000 users=1000000 documents=10000000
```

Override order:

```text
orgs teams groups users documents checks
```

The same order is used by both `load` and `load-plan`.

The realistic load shape intentionally does not model per-document-user `active` relations. Activity is modeled at org scope with `org#active_member@user`, avoiding a document-by-user matrix.

Generated checks intentionally mix allowed, banned, and denied cases. Allowed checks include direct active document viewer paths, document viewer group paths, parent/folder traversal, team traversal, and org-admin traversal. Banned checks use selected documents where an otherwise allowed active viewer is explicitly banned, and denied checks use users outside the document's generated viewer path.

`load-plan` also prints the matching `load` command. If that target is too large for the in-memory prototype, `load` refuses to materialize it and prints the estimated tuple count plus memory-estimate components.

`load-plan` remains a sizing estimator. The `load` command is the measured materialized run: it reports build-phase and check-phase wall time, process CPU time, application allocation memory, tuple lookup mode, compact forward-index sizes, dense traversal-index sizes, per-worker memo size estimates, check latency percentiles, throughput, and the active execution model. It keeps raw machine-readable metric lines and also prints a human-readable summary with seconds, GiB, percentages, per-check graph work, memo footprint, and latency units. Application allocation memory is measured through the prototype's allocator wrapper; it is not OS RSS.

Use `zig build run-fast -- load ...` for non-trivial load runs. The default `zig build run -- load ...` uses Debug optimization and can be orders of magnitude slower because it keeps Zig's development-time safety checks enabled.

Long `load` runs print progress lines to stderr while building IDs, reserving tuple storage, writing tuples, generating checks, and executing checks. Final metrics are still printed to stdout.

`load-plan` also prints a `load_budget_command` sized against the current planning budget. The estimate includes numeric tuple storage, dictionary entries, check-item storage, and fixed process overhead. It is still a preflight guard, not an RSS guarantee; the measured `load` output is the source of truth for actual prototype allocation and latency behavior.

## Fixtures

Prototype fixtures live under [src/fixtures](src/fixtures):

- [src/fixtures/demo/schema.vq](src/fixtures/demo/schema.vq)
- [src/fixtures/demo/tuples.txt](src/fixtures/demo/tuples.txt)
- [src/fixtures/load/schema.vq](src/fixtures/load/schema.vq)
- [src/fixtures/load/tuples.example.txt](src/fixtures/load/tuples.example.txt)
- [src/fixtures/tests](src/fixtures/tests)

The `demo` command loads the demo schema and tuples from fixture files. The `load` command loads its schema from fixture files and generates deterministic tuples/checks from the synced load parameters.

## Correctness Tests

`zig build test` runs fixture-backed DSL and check-engine cases from [src/fixtures/tests](src/fixtures/tests). Each scenario has separate `schema.vq`, `tuples.txt`, and `checks.txt` files.

Current fixture coverage includes:

- permission operators: union, intersection, and difference
- userset subjects and nested group membership
- traversal across parent/team/org relationships
- public `check` behavior for allowed, denied, and fail-closed decisions
- cycle detection in userset recursion
- read-after-revoke behavior through a focused delete/index rebuild test
