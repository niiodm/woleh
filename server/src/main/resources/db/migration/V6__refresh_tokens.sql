-- Phase 3 step 2.4 — opaque refresh tokens for FR-A2.
--
-- Raw tokens are never stored; only SHA-256 hex digests are persisted.
-- Rotation: old row is marked revoked=true, a new row is inserted.
-- ON DELETE CASCADE lets test teardown (deleteAll on users) work cleanly.

CREATE TABLE refresh_tokens (
    id          BIGSERIAL    PRIMARY KEY,
    user_id     BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(64)  NOT NULL,
    expires_at  TIMESTAMPTZ  NOT NULL,
    revoked     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash)
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens (user_id);
