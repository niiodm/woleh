# ADR 0007: Single-tenant deployment for Woleh v1

## Status

Accepted

## Context

[PRD.md](../PRD.md) §13.3 allows reusing the backend for other discovery apps later.

## Decision

- **v1:** Run **one deployment** serving **Woleh** only: single database, single set of `woleh.*` permissions, no tenant id in JWT.
- **Future:** A second product or strict isolation requires a new ADR (multi-tenant schema, separate deployments, or API gateway routing).

## Consequences

**Positive:** Fastest path to launch; simpler auth and billing.

**Negative:** Forking the codebase or adding `tenant_id` later may require migration—acceptable for stated roadmap.

## Date

2026-04-06
