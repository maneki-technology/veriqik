# 0006 Defer Consensus Protocol Selection

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik will defer choosing Paxos, Raft, or another consensus protocol until the replication phase.

The docs will specify consensus requirements now, but not bind MVP 1 to a specific distributed protocol.

## Context

MVP 1 is single-node. Consensus is out of scope until replication and distributed revisions.

Choosing a protocol too early can distract from the core authorization database model. At the same time, the single-node design should not block future replication.

## Considered Options

- Choose Raft now.
- Choose Paxos or Multi-Paxos now.
- Defer protocol selection and specify required properties.

## Rationale

Deferring protocol selection preserves focus while still shaping the right abstractions.

Required future properties:

- one leader per shard epoch
- total order of command batches
- quorum commit
- deterministic replay
- committed, applied, and published revisions
- catch-up
- snapshot shipping
- failover without losing committed authorization history
- membership-change strategy

Raft is the pragmatic default candidate because its leader, term, log, commit index, and snapshot concepts map cleanly to Veriqik's distributed vocabulary. This ADR does not accept Raft yet.

## Consequences

- MVP 1 can implement a clean single-node state machine without consensus code.
- Future replication design has explicit requirements.
- Some storage/log abstractions should avoid assuming there will only ever be one local WAL.

## Confidence

Medium.

Reevaluate when starting replication design, especially after benchmarking single-node write paths and recovery behavior.

## Supersedes

None.

## Superseded By

None.
