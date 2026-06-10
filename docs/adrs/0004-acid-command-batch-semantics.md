# 0004 ACID Command-Batch Semantics

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik MVP 1 will provide ACID command-batch semantics for its domain-specific single-node state machine.

This does not mean Veriqik is a general SQL database. The guarantee applies to Veriqik commands such as `write_schema`, `write_relationships`, and `delete_relationships`.

## Context

Authorization correctness depends on clear visibility and durability rules. Relationship writes, revocations, schema changes, indexes, and revisions must not become partially visible.

Veriqik stores domain-specific authorization state, but it should still behave like a database for committed command batches.

## Considered Options

- Avoid ACID terminology and describe only individual invariants.
- Claim full SQL-style ACID.
- Claim domain-specific ACID command-batch semantics.

## Rationale

Domain-specific ACID command-batch semantics are precise enough to guide implementation without overclaiming SQL behavior.

Mapping:

- Atomicity: a command batch is fully visible or not visible.
- Consistency: committed commands preserve schema, tuple, tenant, index, revision, and permission invariants.
- Isolation: writes are serialized and reads/checks evaluate one stable revision.
- Durability: committed writes survive restart through WAL and recovery.

## Consequences

- The write path must fsync the WAL before publishing a revision.
- Check and batch-check APIs must capture stable evaluated revisions.
- Indexes must be updated atomically with revision publication.
- Tests should include crash, replay, and partial-visibility cases.

## Confidence

High.

Reevaluate only if Veriqik changes from a durable database into a stateless policy service, which is not the current product direction.

## Supersedes

None.

## Superseded By

None.
