-- Phase 2 step 2.2 — per-user place-name lists for watch and broadcast flows.
--
-- Each user has at most one row per list_type (enforced by the unique constraint).
-- Both display_names and normalized_names are stored as JSON arrays of strings:
--   display_names   — original user-entered text (returned to client for display)
--   normalized_names — result of PlaceNameNormalizer.normalize() (used for matching queries)
--
-- Storing the normalized form avoids re-normalizing on every matching query.
-- If the normalization algorithm changes, a follow-up migration must re-normalize all rows.

CREATE TABLE user_place_lists (
    id               BIGSERIAL    PRIMARY KEY,
    user_id          BIGINT       NOT NULL REFERENCES users(id),
    list_type        VARCHAR(10)  NOT NULL CHECK (list_type IN ('WATCH', 'BROADCAST')),
    display_names    TEXT         NOT NULL DEFAULT '[]',
    normalized_names TEXT         NOT NULL DEFAULT '[]',
    updated_at       TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uq_user_place_lists_user_list UNIQUE (user_id, list_type)
);

-- Speeds up per-user lookups and matching scans by list_type.
CREATE INDEX idx_user_place_lists_user_id   ON user_place_lists (user_id);
CREATE INDEX idx_user_place_lists_list_type ON user_place_lists (list_type);
