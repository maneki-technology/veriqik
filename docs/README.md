# Veriqik Documentation

**Tagline:** A purpose-built database for fine-grained authorization.

This directory contains the product, domain, and technical design docs for Veriqik.

## Reading Order

1. [Product Documentation](product/README.md)
   Starts with the product thesis, then product wedge hypotheses and discovery backlog.

2. [Product Thesis](product/Thesis.md)
   States the product bet and what Veriqik must prove.

3. [Product Wedge Template](product/Wedge_Template.md)
   Captures draft hypotheses for the first customer, first winning workload, adoption path, proof points, and product failure modes.

4. [Domain Language](domain/Domain_Language.md)
   Defines the ubiquitous language for authorization, database, explainability, and distributed database concepts.

5. [Prototype Lessons Learned](product/Prototype_Lessons_Learned.md)
   Summarizes evidence and implementation lessons from the current prototype and generated load tests.

6. [Architecture Decision Records](adrs/README.md)
   Records proposed, accepted, and superseded architectural decisions.

7. [High-Level Roadmap](plans/High_Level_Roadmap.md)
   Describes the long-term product direction and phased roadmap.

8. [MVP 1 Plan](plans/MVP1.md)
   Describes the first implementation goal, scope, milestones, success demo, and acceptance criteria.

9. [MVP 1 Technical Specification](specs/mvp1/Technical_Spec.md)
   Defines the current detailed implementation contract for the single-node MVP.

10. [MVP 1 Spec Map](specs/mvp1/README.md)
   Provides a focused map through the large MVP 1 technical spec and names the future split points.

## Document Roles

| Area | Purpose |
|---|---|
| `product/` | Product thesis, wedge hypotheses, discovery backlog, benchmark wedge template, prototype lessons |
| `domain/` | Stable vocabulary, DDD model, naming rules, anti-corruption language |
| `plans/` | Product direction, roadmap, milestones, scope, acceptance criteria |
| `specs/` | Normative implementation behavior and testable contracts |
| `adrs/` | Short decision records with context, alternatives, consequences, and status |

## Writing Rules

- Keep domain docs stable and implementation-neutral.
- Keep plan docs directional: what, why, and in what order.
- Keep spec docs normative, precise, and testable.
- Prefer Veriqik domain terms from the domain language doc.
- Avoid duplicating long scope or invariant lists across docs; link to the source document instead.

## Normative Language

Technical specs use these terms deliberately:

- `MUST`: required for correctness or compatibility.
- `SHOULD`: expected unless there is a documented reason not to.
- `MAY`: optional behavior.
