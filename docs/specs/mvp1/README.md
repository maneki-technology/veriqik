# MVP 1 Specification Map

The current MVP 1 technical specification lives in [MVP1_Technical_Spec.md](../MVP1_Technical_Spec.md).

That file is intentionally complete, but it is large. This map names the implementation areas and the future split points.

## Current Spec Areas

| Area | Source section |
|---|---|
| Purpose and scope | [Purpose](../MVP1_Technical_Spec.md#1-purpose), [MVP 1 Scope](../MVP1_Technical_Spec.md#3-mvp-1-scope) |
| Database model | [Database Design Model](../MVP1_Technical_Spec.md#41-database-design-model) |
| Schema and DSL | [Schema DSL](../MVP1_Technical_Spec.md#8-schema-dsl), [Schema IR](../MVP1_Technical_Spec.md#9-schema-ir) |
| Commands and canonical encoding | [Commands](../MVP1_Technical_Spec.md#11-commands) |
| Revisions and concurrency | [Revision Model](../MVP1_Technical_Spec.md#12-revision-model), [Single-Node Concurrency Model](../MVP1_Technical_Spec.md#121-single-node-concurrency-model) |
| Storage and recovery | [Storage](../MVP1_Technical_Spec.md#13-storage), [Recovery](../MVP1_Technical_Spec.md#14-recovery), [Deferred Checkpoints](../MVP1_Technical_Spec.md#15-deferred-checkpoints) |
| Indexes | [Indexes](../MVP1_Technical_Spec.md#16-indexes) |
| Check engine | [Check API](../MVP1_Technical_Spec.md#17-check-api), [Check Algorithm](../MVP1_Technical_Spec.md#18-check-algorithm), [Cycle Detection](../MVP1_Technical_Spec.md#19-cycle-detection), [Memoization](../MVP1_Technical_Spec.md#20-memoization), [Traversal Limits](../MVP1_Technical_Spec.md#21-traversal-limits) |
| Explain and batch checks | [Explain-One](../MVP1_Technical_Spec.md#22-explain-one), [Batch Check](../MVP1_Technical_Spec.md#23-batch-check) |
| API, health, errors, security | [Public API](../MVP1_Technical_Spec.md#25-public-api), [Error Model](../MVP1_Technical_Spec.md#27-error-model), [MVP Security Model](../MVP1_Technical_Spec.md#272-mvp-security-model) |
| Tests and benchmarks | [Acceptance Tests](../MVP1_Technical_Spec.md#29-acceptance-tests), [Test Strategy](../MVP1_Technical_Spec.md#291-test-strategy), [Benchmark Contract](../MVP1_Technical_Spec.md#292-benchmark-contract) |

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
