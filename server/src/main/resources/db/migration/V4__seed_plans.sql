-- Phase 1 step 2.1 — seed v1 plan catalog (PRD §13.1, §13.5).
-- NOTE (dev/test): woleh_free has all permissions and unlimited caps for local testing.
-- woleh_paid_monthly is priced at GHS 1.00 (100 pesewas) for low-cost payment testing.
-- Adjust limits and pricing before production launch.
-- permissions_granted is a JSON array string matched by StringListConverter.

INSERT INTO plans (plan_id, display_name, permissions_granted, price_amount_minor, price_currency, place_watch_max, place_broadcast_max, active)
VALUES
    ('woleh_free',
     'Free',
     '["woleh.account.profile","woleh.plans.read","woleh.place.watch","woleh.place.broadcast"]',
     0, 'GHS', 999999999, 999999999, true),

    ('woleh_paid_monthly',
     'Woleh Pro',
     '["woleh.account.profile","woleh.plans.read","woleh.place.watch","woleh.place.broadcast"]',
     100, 'GHS', 999999999, 999999999, true);
