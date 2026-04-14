-- Saved place list templates: user-owned, shareable by opaque token.
-- display_names / normalized_names are JSON arrays of strings (same convention as user_place_lists).

CREATE TABLE user_saved_place_lists (
    id BIGSERIAL    PRIMARY KEY,
    user_id           BIGINT       NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title             VARCHAR(255),
    share_token       VARCHAR(64)  NOT NULL,
    display_names     TEXT         NOT NULL DEFAULT '[]',
    normalized_names  TEXT         NOT NULL DEFAULT '[]',
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_saved_place_lists_share_token UNIQUE (share_token)
);

CREATE INDEX idx_user_saved_place_lists_user_id ON user_saved_place_lists (user_id);
