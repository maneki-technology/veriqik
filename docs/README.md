# Veriqik Documentation

**Tagline:** A purpose-built database for fine-grained authorization.

This directory contains the product, domain, and technical design docs for Veriqik.

## Reading Order

1. [Product Thesis](Product_Thesis.md)
   States the product bet and what Veriqik must prove.

2. [Product Wedge Template](Product_Wedge.md)
   Captures draft hypotheses for the first customer, first winning workload, adoption path, proof points, and product failure modes.

3. [Domain Language](domain/Domain_Language.md)
   Defines the ubiquitous language for authorization, database, explainability, and distributed database concepts.

4. [Architecture Decision Records](adrs/README.md)
   Records proposed, accepted, and superseded architectural decisions.

5. [High-Level Roadmap](plans/High_Level_Roadmap.md)
   Describes the long-term product direction and phased roadmap.

6. [MVP 1 Plan](plans/MVP1.md)
   Describes the first implementation goal, scope, milestones, success demo, and acceptance criteria.

7. [MVP 1 Technical Specification](specs/mvp1/Technical_Spec.md)
   Defines the current detailed implementation contract for the single-node MVP.

8. [MVP 1 Spec Map](specs/mvp1/README.md)
   Provides a focused map through the large MVP 1 technical spec and names the future split points.

## Document Roles

| Area | Purpose |
|---|---|
| `Product_Thesis.md` | Product bet, competitive frame, differentiator, proof points |
| `Product_Wedge.md` | Draft product wedge template: first customer, first pain, winning workload, adoption path, failure modes |
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
