# Release signing

CI signs APKs with a release key supplied through repository secrets
(`.github/scripts/setup-signing.sh` writes `android/app/release.jks` and
`android/key.properties` before the build). Neither file should be in git:
`.gitignore` already excludes `key.properties` and `*.jks`.

## Why the key must not be committed

Anyone who has the key and its password can build an APK that Android accepts
as an **update** of an installed Finance Tracker. An update inherits the app's
private data directory (the transaction database, the SQLCipher key reference)
and its granted permissions, including READ_SMS. In a public repository that
means anyone.

## Secrets

Add these under **Settings → Secrets and variables → Actions → New repository
secret**:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.jks` (macOS: `base64 -i release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | the key alias |
| `ANDROID_KEY_PASSWORD` | the key password |

Until `ANDROID_KEYSTORE_BASE64` is set, CI keeps signing with the committed
`android/key.properties` (with a warning), so nothing breaks mid-migration.
Once that file is gone, a push to `main` without the secrets fails loudly
rather than producing a debug-signed APK; pull requests (which never see
secrets from forks) build debug-signed with a warning.

## Migrating off the committed key

The old key (`android/app/finance-release.jks`, password in
`android/key.properties`) has been public, so treat it as compromised. Two
options:

### A. Rotate to a new key (recommended)

1. **Back up first** (Backup & Export → Drive or local file). Android refuses
   to install an APK signed with a different key over the existing app, so
   you will uninstall and reinstall.
2. Create a key, kept outside the repository:
   ```sh
   keytool -genkeypair -v -keystore release.jks -alias finance \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
3. Add the four secrets above from it.
4. Delete the committed key from the repository:
   ```sh
   git rm android/key.properties android/app/finance-release.jks
   git commit -m "Stop committing the release signing key"
   ```
5. Register the new key's SHA-1 for Google Drive sign-in
   (`keytool -list -v -keystore release.jks -alias finance`, then follow
   `docs/GOOGLE_DRIVE_SETUP.md` section 2 onward with that fingerprint).
6. Uninstall the app, install the new CI build, restore the backup.

### B. Keep the old key, just move it to secrets

Steps 3–4 only, using the existing `finance-release.jks`. Updates and Drive
keep working with no reinstall, but the key stays compromised: it remains in
git history, and removing it from history does not un-publish it from
existing clones. Only rotation (A) closes the hole.

## Local release builds

Put your own `android/key.properties` next to the keystore (see the comment
at the top of `android/app/build.gradle.kts`). Without it, `flutter build apk
--release` signs with the debug key.
