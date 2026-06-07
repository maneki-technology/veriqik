# 0001 Record Architecture Decisions in Repo

Status: Proposed

Date: 2026-06-07

## Decision

Veriqik will record important architecture decisions as numbered Markdown ADRs under `docs/adrs`.

ADRs will start as `Proposed`, move to `Accepted` when the team chooses to rely on them, and become `Superseded` when replaced by a later ADR.

## Context

Veriqik is still in early design, but it is already making architectural choices about domain semantics, database guarantees, distributed consistency, and implementation boundaries.

These choices should be easy to review, discuss, and revisit without burying rationale in long specs.

## Considered Options

- Keep decisions only in technical specs.
- Keep decisions in external planning tools.
- Keep lightweight ADRs in the repository.

## Rationale

Repository ADRs keep decisions near the docs and future code they affect. They are easy to diff, review, link, and preserve in history.

Specs remain the detailed contract. ADRs capture why important choices were made.

## Consequences

- The repo gains a small decision log.
- Specs can link to ADRs for rationale instead of repeating long trade-off discussions.
- Proposed ADRs may become stale if they are not accepted, rejected, or superseded.

## Confidence

High.

Reevaluate if ADRs become too heavy or duplicate the specs instead of explaining decisions.

## Supersedes

None.

## Superseded By

None.
