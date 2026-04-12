# Product analytics events (mobile)

Firebase Analytics (GA4) events logged by the Flutter app. Parameter values are **strings or numbers** (Firebase SDK constraint). Screen transitions also emit the standard **`screen_view`** event via `FirebaseAnalyticsObserver` on `GoRouter` routes that define a `name`.

**User id:** After sign-in, `GET /me` resolves `profile.userId`; that value is passed to `setUserId`. It is cleared on sign-out.

**Opt-out / consent:** Compile-time `--dart-define=WOLEH_FIREBASE_ANALYTICS=false`, or in-app **product analytics** opt-in (phone screen + Profile; server-backed; Consent Mode) when Firebase is active — see [`docs/PRIVACY_TELEMETRY.md`](PRIVACY_TELEMETRY.md) and [`mobile/README.md`](../mobile/README.md).

| Event | Parameters | When |
|-------|------------|------|
| `screen_view` | (automatic) `firebase_screen`, `firebase_screen_class` | Route changes (named `GoRoute`s). |
| `auth_completed` | `is_signup` — `1` new user, `0` returning | After OTP verification and token persistence. |
| `setup_name_completed` | `action` — `save` \| `skip` \| `continue_empty` | End of display-name onboarding. |
| `place_watch_saved` | `place_count` — number of names | Watch list saved from place search. |
| `place_broadcast_saved` | `place_count` | Broadcast list saved from place search. |
| `subscription_checkout_started` | `plan_id` — string | User taps Subscribe on a paid plan. |
| `button_tapped` | `button_id`, `screen_name` | Primary CTAs (see below). |

### `button_tapped` — `button_id` values

| `button_id` | `screen_name` |
|-------------|---------------|
| `send_otp` | `/auth/phone` |
| `verify_otp` | `/auth/otp` |
| `resend_otp` | `/auth/otp` |
| `save_and_continue` | `/auth/setup-name` |
| `skip_setup_name` | `/auth/setup-name` |
| `open_places_search` | `/home` |
| `stop_broadcast` / `stop_watch` | `/home` |
| `open_profile` | `/home` |
| `add_place_to_list` | `/places/search` |
| `save_watch_list` | `/places/search` |
| `save_broadcast_list` | `/places/search` |
| `open_plans` / `edit_profile` / `sign_out` | `/profile` |

Staging vs production: use separate Firebase projects or GA4 data filters so test traffic does not pollute production funnels (see [`MONITORING_AND_ANALYTICS_PLAN.md`](MONITORING_AND_ANALYTICS_PLAN.md)).
