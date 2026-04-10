-- Phase 4: match-scoped live location — user opt-in for publishing device fixes (MAP_LIVE_LOCATION_PLAN §3.2–3.4).
ALTER TABLE users
	ADD COLUMN location_sharing_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN users.location_sharing_enabled IS 'When true, POST /api/v1/me/location is accepted (subject to rate limits and match-scoped fan-out).';
