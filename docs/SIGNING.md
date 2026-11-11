# Release signing

CI signs APKs with a release key supplied through repository secrets
(`.github/scripts/setup-signing.sh` writes `android/app/release.jks` and
`android/key.properties` before the build). Neither file is in git:
`.gitignore` excludes `key.properties` and `*.jks`.

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

A push to `main` without the secrets fails loudly rather than producing a
debug-signed APK. Pull requests (which never see secrets from forks) build debug-signed with a
warning. A build started by hand on a branch other than `main` mints a
throwaway key with `keytool` and signs with that: good for trying a branch
out, but each run's key is different, so one try-out build cannot update
another (uninstall first) and Drive sign-in rejects it. The build then prints
the APK's package name, minimum Android version and signature schemes, so a
mis-signed APK is caught in CI rather than on the phone.

## The key that used to be committed

Until 1.48.0 the repository carried a key (`android/app/finance-release.jks`,
password in `android/key.properties`). Both files are deleted now, but they
remain in git history and in every existing clone, so **treat that key as
compromised** and do not put it into the secrets. Rotate instead:

1. **Back up first** (Backup & Export → Drive or a downloaded file). Android
   refuses to install an APK signed with a different key over the existing
   app, so you will uninstall and reinstall.
2. Create a key, kept outside the repository:
   ```sh
   keytool -genkeypair -v -keystore release.jks -alias finance \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
3. Add the four secrets above from it.
4. Register the new key's SHA-1 for Google Drive sign-in
   (`keytool -list -v -keystore release.jks -alias finance`, then follow
   `docs/GOOGLE_DRIVE_SETUP.md` section 2 onward with that fingerprint), and
   remove the old key's SHA-1 from the OAuth client.
5. Uninstall the app, install the new CI build, restore the backup.

## Local release builds

Put your own `android/key.properties` next to the keystore (see the comment
at the top of `android/app/build.gradle.kts`). Without it, `flutter build apk
--release` signs with the debug key.
