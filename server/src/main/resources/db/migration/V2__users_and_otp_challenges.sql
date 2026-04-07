-- Users: created only after successful OTP verification (ADR 0003).
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    phone_e164 VARCHAR(20) NOT NULL UNIQUE,
    display_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- Pending OTP challenges (ADR 0002): hashed value, expiry, attempt cap, single-use.
CREATE TABLE otp_challenges (
    id BIGSERIAL PRIMARY KEY,
    phone_e164 VARCHAR(20) NOT NULL,
    otp_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_otp_challenges_phone_e164 ON otp_challenges (phone_e164);
