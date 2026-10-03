#!/usr/bin/env bash
# Writes the release keystore and android/key.properties from repository
# secrets, so neither has to live in git. Expected environment (set from the
# workflow's `env:` block):
#   ANDROID_KEYSTORE_BASE64   base64 of the .jks file
#   ANDROID_KEYSTORE_PASSWORD store password
#   ANDROID_KEY_ALIAS         key alias
#   ANDROID_KEY_PASSWORD      key password
# See docs/SIGNING.md for how to create them.
set -euo pipefail

if [[ -z "${ANDROID_KEYSTORE_BASE64:-}" && -f android/key.properties ]]; then
  # Transition: the key is still committed. Keep signing with it so builds
  # stay installable over existing copies until the secrets are added.
  echo "::warning::Signing with the key committed to the repository. Move it to secrets and delete it from git (docs/SIGNING.md)."
  exit 0
fi

if [[ -z "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  # Pull requests from forks never see secrets. Let those still build (with
  # the debug key, see android/app/build.gradle.kts) but never ship a
  # debug-signed APK from main: it could not update an installed copy and
  # Drive sign-in would reject it.
  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    echo "::warning::ANDROID_KEYSTORE_BASE64 is not set; this APK is debug-signed and cannot update an installed release build."
    exit 0
  fi
  echo "::error::ANDROID_KEYSTORE_BASE64 is not set. Add the signing secrets described in docs/SIGNING.md."
  exit 1
fi

echo "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android/app/release.jks
cat > android/key.properties <<PROPS
storeFile=app/release.jks
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
keyPassword=${ANDROID_KEY_PASSWORD}
PROPS
