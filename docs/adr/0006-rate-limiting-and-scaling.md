# ADR 0006: Rate limiting and scaling (MVP vs multi-instance)

## Status

Accepted

## Context

[ARCHITECTURE.md](../ARCHITECTURE.md) describes in-memory rate limits for some endpoints; multiple API instances break purely in-memory counters.

## Decision

- **MVP / single instance:** Use **in-memory** rate limiters (per IP, per user id, per phone) where specified (e.g. OTP in ADR 0002, optional location-style endpoints later).
- **Multi-instance or pre-production hardening:** Move hot counters to **Redis** (or API gateway limits) and document migration in deployment runbooks.
- **Idempotency keys:** Persist in **Redis or database** with TTL when horizontal scaling is introduced (not required for first single-node deploy).

## Consequences

**Positive:** Simple ops for early launch; clear upgrade path.

**Negative:** Risk of inconsistent limits for seconds during split-brain if Redis migration is delayed—acceptable for low initial scale.

## Date

2026-04-06
