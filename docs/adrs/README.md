# Architecture Decision Records

This directory contains Veriqik Architecture Decision Records (ADRs).

ADRs are short records for important architectural decisions. They are numbered, kept in source control, and written in Markdown so they can be reviewed and diffed like code.

Reference: [Martin Fowler, Architecture Decision Record](https://martinfowler.com/bliki/ArchitectureDecisionRecord.html).

## Status Values

- `Proposed`: under discussion; not yet binding.
- `Accepted`: active decision.
- `Superseded`: replaced by a later ADR.

Accepted ADRs should not be rewritten to change the decision. Add a new ADR that supersedes the old one.

## Index

ADR 0001 records the ADR process. The remaining proposed ADRs are ordered by architectural importance and reading relevance. Once an ADR is accepted, its number should remain stable; future changes should supersede it with a new ADR.

| ADR | Status | Title |
|---|---|---|
| [0001](0001-record-architecture-decisions-in-repo.md) | Proposed | Record Architecture Decisions in Repo |
| [0002](0002-build-domain-specific-authorization-database.md) | Proposed | Build a Domain-Specific Authorization Database |
| [0003](0003-use-zed-inspired-veriqik-dsl.md) | Proposed | Use a Zed-Inspired Veriqik DSL |
| [0004](0004-public-check-and-internal-eval-boundary.md) | Proposed | Public Check and Internal Eval Boundary |
| [0005](0005-acid-command-batch-semantics.md) | Proposed | ACID Command-Batch Semantics |
| [0006](0006-consistency-over-availability-for-fresh-authorization.md) | Proposed | Consistency Over Availability for Fresh Authorization |
| [0007](0007-defer-consensus-protocol-selection.md) | Proposed | Defer Consensus Protocol Selection |

## Template

Use [template.md](template.md) for new ADRs.
