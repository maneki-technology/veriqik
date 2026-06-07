# 0006 Consistency Over Availability for Fresh Authorization

Status: Proposed

Date: 2026-06-07

## Decision

Distributed Veriqik will prioritize consistency over availability for writes and freshness-constrained authorization reads.

If a replica cannot satisfy the requested minimum revision, it must wait, redirect, or reject. It must not answer from a stale revision while claiming freshness.

## Context

Authorization systems have a safety problem that many generic read-heavy systems can avoid: stale reads after revocation can incorrectly grant access.

Veriqik's distributed design needs explicit language for read-after-write and read-after-revoke behavior.

## Considered Options

- Prefer availability and allow silent stale reads.
- Prefer consistency for all reads and reject any stale read.
- Prefer consistency for writes and freshness-constrained reads, while allowing explicitly requested stale/bounded-staleness modes later.

## Rationale

Silent stale reads are unsafe for revocation-sensitive authorization. However, some future workloads may choose explicit bounded staleness for lower-risk checks.

The core safety rule is tied to the requested consistency mode:

```text
at_least(revision)
```

A replica that has not published that revision cannot safely answer.

## Consequences

- During partitions, some writes or fresh reads may become unavailable.
- Clients can enforce read-after-revoke using revision tokens.
- Future follower reads must check published revision before answering.
- Availability-oriented modes must be explicit and opt-in.

## Confidence

High.

Reevaluate only if Veriqik introduces a clearly separated low-sensitivity read mode with strong product warnings.

## Supersedes

None.

## Superseded By

None.
