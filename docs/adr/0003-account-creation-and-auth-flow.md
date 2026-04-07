# ADR 0003: Account creation timing and `flow` field

## Status

Accepted

## Context

The API must return `login` vs `signup` after OTP verification without the client sending `purpose` ([API_CONTRACT.md](../API_CONTRACT.md) §6.2).

## Decision

1. **Existing number:** On successful `verify-otp`, if a user row already exists for `phoneE164`, issue tokens and return `"flow": "login"`.
2. **New number:** Create the **user row only after** OTP verification succeeds (not at `send-otp`). Then issue tokens and return `"flow": "signup"`.
3. **Idempotency:** `verify-otp` for an already-consumed OTP returns **400** with a clear message; do not double-create users.

This keeps `flow` authoritative and avoids orphan users who never verified.

## Consequences

**Positive:** Clear semantics; matches user expectation of “verified phone = account exists.”

**Negative:** `send-otp` cannot reserve a username globally without extra tables—out of scope for v1.

## Date

2026-04-06
