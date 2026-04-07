# ADR 0001: WebSocket authentication (query token)

## Status

Accepted

## Context

Mobile WebSocket clients vary in support for custom headers on the HTTP upgrade request. Spring Security and many stacks need a clear rule for passing JWTs during `wss` handshake.

## Decision

- Pass the JWT as a **query parameter**: `wss://<host>/ws/v1/transit?access_token=<jwt>`.
- Require **TLS** (`wss://`) in non-development environments so the URL is not sent in cleartext.
- Reject handshake with **403** when the token is missing, invalid, or expired.
- Validate the same claims as REST (subject = user id); enforce stream permissions per [API_CONTRACT.md](../API_CONTRACT.md) §8.

## Consequences

**Positive:** Works consistently across Flutter `web_socket_channel` and typical mobile stacks; easy to document and test.

**Negative:** Tokens may appear in access logs if servers log full URLs—mitigate with structured logging that redacts `access_token`, and prefer reasonable JWT TTL.

**Neutral:** Alternative (subprotocol or `Authorization` header) rejected for mobile compatibility first.

## Date

2026-04-06
