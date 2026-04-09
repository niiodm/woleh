-- Phase 1 step 2.1 — subscription plan catalog, user subscriptions, and payment sessions.

-- Plan catalog: each plan defines a set of permissions and limits.
-- permissions_granted is stored as a JSON array string (e.g. '["woleh.place.watch"]').
CREATE TABLE plans (
    id                  BIGSERIAL PRIMARY KEY,
    plan_id             VARCHAR(100) NOT NULL UNIQUE,
    display_name        VARCHAR(255) NOT NULL,
    permissions_granted TEXT        NOT NULL,
    price_amount_minor  INTEGER     NOT NULL,
    price_currency      VARCHAR(3)  NOT NULL DEFAULT 'GHS',
    place_watch_max     INTEGER     NOT NULL,
    place_broadcast_max INTEGER     NOT NULL,
    active              BOOLEAN     NOT NULL DEFAULT TRUE
);

-- User subscriptions: one active row per user at a time (enforced by application logic).
-- grace_period_end = current_period_end + 7 days (PRD §13.6).
CREATE TABLE subscriptions (
    id                       BIGSERIAL    PRIMARY KEY,
    user_id                  BIGINT       NOT NULL REFERENCES users(id),
    plan_id                  BIGINT       NOT NULL REFERENCES plans(id),
    status                   VARCHAR(20)  NOT NULL,
    current_period_start     TIMESTAMPTZ  NOT NULL,
    current_period_end       TIMESTAMPTZ  NOT NULL,
    grace_period_end         TIMESTAMPTZ  NOT NULL,
    provider_subscription_id VARCHAR(255),
    created_at               TIMESTAMPTZ  NOT NULL,
    updated_at               TIMESTAMPTZ  NOT NULL
);

CREATE INDEX idx_subscriptions_user_id ON subscriptions (user_id);

-- Payment sessions: tracks a checkout attempt from initiation to provider confirmation.
CREATE TABLE payment_sessions (
    id                 BIGSERIAL    PRIMARY KEY,
    user_id            BIGINT       NOT NULL REFERENCES users(id),
    plan_id            BIGINT       NOT NULL REFERENCES plans(id),
    session_id         VARCHAR(255) NOT NULL UNIQUE,
    provider_reference VARCHAR(255),
    status             VARCHAR(20)  NOT NULL,
    checkout_url       TEXT         NOT NULL,
    expires_at         TIMESTAMPTZ  NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL
);

CREATE INDEX idx_payment_sessions_user_id ON payment_sessions (user_id);
