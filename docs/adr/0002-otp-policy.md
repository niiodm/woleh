# ADR 0002: OTP issuance and verification policy

## Status

Accepted

## Context

Phone OTP is the primary auth factor. We need predictable security and abuse limits without over-specifying the SMS vendor.

## Decision

| Rule | Value |
|------|--------|
| OTP format | **6** decimal digits |
| OTP TTL | **5 minutes** from issue |
| Hash at rest | **BCrypt** (or Argon2 if available) of the OTP value; never store plaintext |
| Send OTP rate limit | **3** successful `send-otp` requests per **E.164 number per rolling hour** (HTTP 429 when exceeded) |
| Verify attempts | **5** failed verifications per issued OTP; then invalidate OTP and require new send |
| Lockout | Optional short lockout after repeated abuse from same IP/number (implementation detail) |

Development may log OTP to console; production uses real SMS through the provider.

## Consequences

**Positive:** Aligns with common mobile OTP practice; limits credential stuffing on verify.

**Negative:** Users who mistype repeatedly must request a new OTP—acceptable tradeoff.

## Date

2026-04-06
