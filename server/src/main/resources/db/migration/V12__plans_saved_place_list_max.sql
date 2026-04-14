-- Max number of saved place list templates per user (enforced in application from plan / free tier).

ALTER TABLE plans
    ADD COLUMN saved_place_list_max INTEGER NOT NULL DEFAULT 20;
