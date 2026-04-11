-- Default location sharing on for new users; opt-out remains via PUT /me/location-sharing.
ALTER TABLE users
	ALTER COLUMN location_sharing_enabled SET DEFAULT TRUE;

UPDATE users
SET location_sharing_enabled = TRUE
WHERE location_sharing_enabled = FALSE;
