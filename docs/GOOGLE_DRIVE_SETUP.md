# Enabling Google Drive backup

The **Backup to Google Drive** / **Restore from Google Drive** buttons use
Google Sign-In. If you see an error like:

```
PlatformException(sign_in_failed,
  com.google.android.gms.common.api.ApiException: 10: , null, null)
```

that is `DEVELOPER_ERROR` (code 10). It means Google has **no OAuth client
registered** for this app's package name **and** the SHA-1 fingerprint of the
key that signed the APK. This is a one-time setup you do in Google Cloud — it
cannot be fixed on the phone.

> Until this is done, Drive backup will always fail. Your data is still safe:
> use **Backup locally (JSON)** or **Encrypted backup (JSON)** — those work
> with no sign-in.

## What you need to know first

Google matches the Android OAuth client by **package name + signing SHA-1**.
So the SHA-1 you register must belong to the exact key that signs the APK
people install:

- APKs built by CI here are signed with the **debug key** (see
  `android/app/build.gradle.kts`). Every debug keystore is different, so a
  debug-signed APK from CI has a different SHA-1 than one built on your laptop.
- For a real, shareable build, sign with a single **release keystore** and
  register that key's SHA-1 (set up `android/key.properties`).

The app id is `com.example.finance_tracker` (see `applicationId` in
`android/app/build.gradle.kts`). Change it to your own before publishing.

## 1. Get the signing certificate SHA-1

Debug key (quick test builds):

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android | grep SHA1
```

Or, from the `android/` folder, for whatever key the build is configured to use:

```bash
cd android && ./gradlew signingReport
```

Release key (shareable builds): run `keytool -list -v` against your release
`.jks` with its alias/passwords.

Copy the `SHA1:` value.

## 2. Create a Google Cloud project

1. Go to https://console.cloud.google.com/ and create a project.
2. **APIs & Services → Library →** enable the **Google Drive API**.

## 3. Configure the OAuth consent screen

1. **APIs & Services → OAuth consent screen.**
2. User type: **External**.
3. Fill in app name / support email.
4. **Scopes:** add
   - `.../auth/drive.file`
   - `.../auth/drive.appdata`
5. **Test users:** add the Google account(s) you'll sign in with.
   (While the app is in "Testing", only these accounts can sign in.)

## 4. Create the Android OAuth client ID

1. **APIs & Services → Credentials → Create credentials → OAuth client ID.**
2. Application type: **Android**.
3. Package name: `com.example.finance_tracker` (or your own app id).
4. SHA-1: paste the value from step 1.
5. Create.

For basic Drive `drive.file` / `appdata` sign-in on Android, the
`google_sign_in` plugin picks up this Android client automatically from the
package name + SHA-1 — you do **not** need to add a `google-services.json` or
embed the client id in the app.

## 5. Rebuild and test

Reinstall the app built with the **same key** whose SHA-1 you registered, then
tap **Backup to Google Drive**. Sign in with a test-user account.

## Common gotchas

- **Still ApiException: 10** → the SHA-1 or package name doesn't match. Double
  check you registered the SHA-1 of the key that actually signed the installed
  APK (debug vs release), and that the package name is exact.
- **Access blocked / not a test user** → add the account under
  OAuth consent screen → Test users (or publish the consent screen).
- **Multiple build machines** → each debug keystore has its own SHA-1. Add each
  one, or standardize on a shared release key.
- Registration changes can take a few minutes to propagate.
