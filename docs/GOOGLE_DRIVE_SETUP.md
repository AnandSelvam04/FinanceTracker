# Enabling Google Drive backup (personal use, no Play Store)

You do **not** need to publish this app anywhere. Google Drive backup works
privately: you register your app once in Google Cloud, add your own Gmail as a
"test user," and only you can sign in. "Testing" mode *is* the personal-use
mode — nothing is published or reviewed.

## Your app's values (fill these into the console)

Google matches an Android OAuth client on **package name + signing SHA-1**,
so both halves have to describe the APK you actually install.

| Field | Value |
|-------|-------|
| **Package name** | `io.github.anandselvam04.financetracker` |
| **SHA-1 fingerprint** | of whichever key signs your build — see section 1 |

> **An earlier registration no longer matches.** Up to 1.49 this app was
> registered as `com.example.finance_tracker` with the SHA-1
> `7D:54:82:58:A6:0C:8D:AA:14:2C:B4:09:EF:CC:E6:2B:09:50:12:5E`, the key that
> used to be committed to the repository. **Both** halves have since changed:
> the package name was renamed at 1.50.0, and that key was removed as
> compromised. That OAuth client can be deleted; create a new one.
>
> Registering is only about Drive sign-in. Nothing needs registering for an
> APK to install on your phone.

Settle the signing key **first** (`docs/SIGNING.md`): a try-out build mints a
throwaway key per run, so its SHA-1 changes every build and is not worth
registering. Once CI signs with one stable release key from the repository
secrets, take that key's SHA-1, do sections **2, 3, 4** below, install a fresh
CI build, and sign in with the Gmail you added as a test user.

---

## Background

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

- With the signing secrets set, CI signs every build with that one release
  key, so the SHA-1 stays the same build after build. This is the only setup
  worth registering.
- Without them, a hand-started branch build mints a **throwaway key per run**,
  so its SHA-1 differs every time and Drive sign-in cannot work. Likewise a
  build from your own laptop uses your own debug keystore, with its own SHA-1.

The app id is `io.github.anandselvam04.financetracker` (see `applicationId` in
`android/app/build.gradle.kts`). Until 1.50.0 it was the Flutter template's
`com.example.finance_tracker`. A build with the new id installs as a separate
app beside the old one rather than updating it — back up in the old app,
restore in the new, then uninstall the old.

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
3. Package name: `io.github.anandselvam04.financetracker` (or your own app id).
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
