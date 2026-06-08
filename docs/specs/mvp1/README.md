# MVP 1 Specification Map

The current MVP 1 technical specification lives in [Technical_Spec.md](Technical_Spec.md).

That file is intentionally complete, but it is large. This map names the implementation areas and the future split points.

## Current Spec Areas

| Area | Source section |
|---|---|
| Purpose and scope | [Purpose](Technical_Spec.md#1-purpose), [MVP 1 Scope](Technical_Spec.md#3-mvp-1-scope) |
| Database model | [Database Design Model](Technical_Spec.md#41-database-design-model) |
| Schema and DSL | [Schema DSL](Technical_Spec.md#8-schema-dsl), [Schema IR](Technical_Spec.md#9-schema-ir) |
| Commands and canonical encoding | [Commands](Technical_Spec.md#11-commands) |
| Revisions and concurrency | [Revision Model](Technical_Spec.md#12-revision-model), [Single-Node Concurrency Model](Technical_Spec.md#121-single-node-concurrency-model) |
| Storage and recovery | [Storage](Technical_Spec.md#13-storage), [Recovery](Technical_Spec.md#14-recovery), [Deferred Checkpoints](Technical_Spec.md#15-deferred-checkpoints) |
| Indexes | [Indexes](Technical_Spec.md#16-indexes) |
| Check engine | [Check API](Technical_Spec.md#17-check-api), [Check Algorithm](Technical_Spec.md#18-check-algorithm), [Cycle Detection](Technical_Spec.md#19-cycle-detection), [Memoization](Technical_Spec.md#20-memoization), [Traversal Limits](Technical_Spec.md#21-traversal-limits) |
| Explain and batch checks | [Explain-One](Technical_Spec.md#22-explain-one), [Batch Check](Technical_Spec.md#23-batch-check) |
| API, health, errors, security | [Public API](Technical_Spec.md#25-public-api), [Error Model](Technical_Spec.md#27-error-model), [MVP Security Model](Technical_Spec.md#272-mvp-security-model) |
| Tests and benchmarks | [Acceptance Tests](Technical_Spec.md#29-acceptance-tests), [Test Strategy](Technical_Spec.md#291-test-strategy), [Benchmark Contract](Technical_Spec.md#292-benchmark-contract) |

## Future Split

When implementation starts, split the large spec into these files:

- `Schema.md`
- `Commands.md`
- `Revisions_Concurrency.md`
- `Storage_Recovery.md`
- `Check_Engine.md`
- `API_Health_Errors.md`
- `Testing_Benchmarking.md`

Until then, this map is the stable entry point for implementers.
