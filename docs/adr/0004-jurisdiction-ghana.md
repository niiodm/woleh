# ADR 0004: Operating jurisdiction — Ghana

## Status

Accepted

## Context

Product, payments, and compliance need a single launch geography before expanding.

## Decision

- **Primary jurisdiction:** **Ghana** for v1.
- **Phone numbers:** E.164; **+233** is the expected country code for local users (others may be rejected or deprioritized by product until expansion).
- **Currency:** **GHS** for pricing and payment display unless the provider dictates otherwise.
- **App UI language:** **English** first (per PRD).
- **Data residency:** Host production workloads in a region and provider stack appropriate for **Ghana-facing** launch; exact cloud region and DPA are set at provisioning time and recorded in runbooks, not in this ADR.

Expansion to other countries requires a new ADR and PRD update.

## Consequences

**Positive:** Focused compliance scope; pricing and provider integration align with one market.

**Negative:** International users outside Ghana are out of scope until explicitly supported.

## Date

2026-04-06
