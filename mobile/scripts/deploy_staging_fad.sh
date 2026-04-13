#!/usr/bin/env bash
# Build staging-configured release artifacts and upload to Firebase App Distribution.
#
# Prerequisites:
#   - Flutter SDK (see mobile/pubspec.yaml)
#   - firebase-tools: npm i -g firebase-tools  (or npx firebase-tools@latest)
#   - firebase login  (or FIREBASE_TOKEN from `firebase login:ci` for CI)
#   - Android: android/key.properties + keystore (see android/key.properties.example), or WOLEH_KEYSTORE_* env
#   - iOS: Xcode + Apple Developer Program + valid signing (ad hoc or development for devices)
#
# Environment (optional overrides):
#   WOLEH_BUMP_VERSION=0          skip pubspec version bump
#   API_BASE_URL                  default https://woleh.okaidarkomorgan.com
#   OSM_TILE_URL_TEMPLATE       default https://tile.openstreetmap.org/{z}/{x}/{y}.png
#   ANDROID_FIREBASE_APP_ID       default from this repo's google-services.json
#   IOS_FIREBASE_APP_ID           default from this repo's GoogleService-Info.plist
#   FAD_GROUPS                    comma-separated group aliases (required for upload).
#                                 Use the alias from App Distribution → Testers & groups (often e.g.
#                                 beta-testers), not the display name — wrong alias → HTTP 404 on distribute.
#                                 Must be exported or passed on the same line as the script (see Usage).
#   FIREBASE_TOKEN                CI token when not using interactive login
#   SENTRY_DSN                    optional — forwarded to --dart-define when set
#   SENTRY_ENVIRONMENT            optional — default staging for this script
#   SENTRY_TRACES_SAMPLE_RATE     optional — e.g. 0.2; omit for 0 (errors only)
#   EXTRA_DART_DEFINES            space-separated extra --dart-define=key=value pairs
#
# Usage:
#   FAD_GROUPS=beta-testers ./scripts/deploy_staging_fad.sh android
#   export FAD_GROUPS="beta-testers,qa" && ./scripts/deploy_staging_fad.sh android
#   ./scripts/deploy_staging_fad.sh ios
#   ./scripts/deploy_staging_fad.sh all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${MOBILE_DIR}"

TARGET="${1:-android}"
if [[ "${TARGET}" != "android" && "${TARGET}" != "ios" && "${TARGET}" != "all" ]]; then
  echo "Usage: $0 android|ios|all" >&2
  exit 1
fi

if [[ -z "${FAD_GROUPS:-}" ]]; then
  echo "Set FAD_GROUPS to your Firebase App Distribution tester group aliases (comma-separated)." >&2
  echo "Use: FAD_GROUPS=\"My Group\" $0 android   (or export FAD_GROUPS first — a bare VAR=... && script does not pass it to the child process.)" >&2
  exit 1
fi

if [[ "${WOLEH_BUMP_VERSION:-1}" != "0" ]]; then
  "${SCRIPT_DIR}/bump_version.sh" build
fi

API_BASE_URL="${API_BASE_URL:-https://woleh.okaidarkomorgan.com}"
OSM_TILE_URL_TEMPLATE="${OSM_TILE_URL_TEMPLATE:-https://tile.openstreetmap.org/{z}/{x}/{y}.png}"

DART_DEFINES=(
  "--dart-define=API_BASE_URL=${API_BASE_URL}"
  "--dart-define=OSM_TILE_URL_TEMPLATE=${OSM_TILE_URL_TEMPLATE}"
)

SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT:-staging}"
DART_DEFINES+=("--dart-define=SENTRY_ENVIRONMENT=${SENTRY_ENVIRONMENT}")
if [[ -n "${SENTRY_DSN:-}" ]]; then
  DART_DEFINES+=("--dart-define=SENTRY_DSN=${SENTRY_DSN}")
fi
if [[ -n "${SENTRY_TRACES_SAMPLE_RATE:-}" ]]; then
  DART_DEFINES+=("--dart-define=SENTRY_TRACES_SAMPLE_RATE=${SENTRY_TRACES_SAMPLE_RATE}")
fi

if [[ -n "${EXTRA_DART_DEFINES:-}" ]]; then
  # shellcheck disable=2206
  DART_DEFINES+=(${EXTRA_DART_DEFINES})
fi

ANDROID_APP_ID="${ANDROID_FIREBASE_APP_ID:-1:839161553395:android:7986cb3cebfc70899f7286}"
IOS_APP_ID="${IOS_FIREBASE_APP_ID:-1:839161553395:ios:6c7b26b48975e9e79f7286}"

firebase_cmd() {
  if command -v firebase >/dev/null 2>&1; then
    firebase "$@"
  else
    npx --yes firebase-tools@latest "$@"
  fi
}

fad_upload() {
  local app_id="$1"
  local artifact="$2"
  local token_arg=()
  if [[ -n "${FIREBASE_TOKEN:-}" ]]; then
    token_arg=(--token "${FIREBASE_TOKEN}")
  fi
  firebase_cmd appdistribution:distribute "${artifact}" \
    --app "${app_id}" \
    --groups "${FAD_GROUPS}" \
    "${token_arg[@]}"
}

flutter pub get

if [[ "${TARGET}" == "android" || "${TARGET}" == "all" ]]; then
  flutter build apk --release "${DART_DEFINES[@]}"
  fad_upload "${ANDROID_APP_ID}" "${MOBILE_DIR}/build/app/outputs/flutter-apk/app-release.apk"
fi

if [[ "${TARGET}" == "ios" || "${TARGET}" == "all" ]]; then
  flutter build ipa --release "${DART_DEFINES[@]}"
  shopt -s nullglob
  ipa_files=("${MOBILE_DIR}/build/ios/ipa"/*.ipa)
  shopt -u nullglob
  if [[ ${#ipa_files[@]} -ne 1 ]]; then
    echo "Expected exactly one .ipa under build/ios/ipa; got ${#ipa_files[@]}." >&2
    exit 1
  fi
  fad_upload "${IOS_APP_ID}" "${ipa_files[0]}"
fi
