# Local patches

This is `another_telephony` 0.4.1 as published on pub.dev (without its
example, tests and coverage report), plus one change.

## Only handle this plugin's own permission results

`android/src/main/kotlin/com/shounakmulay/telephony/sms/SmsMethodCallHandler.kt`,
`onRequestPermissionsResult`.

Android delivers every permission result to every plugin; each is expected to
ignore the ones it did not ask for. Upstream's test was

```kotlin
if (requestCode != this.requestCode && !this::action.isInitialized) return false
```

`action` is set by the first method call (reading the inbox, or starting the
incoming-SMS listener at launch), so after that the test never passes and the
plugin treats **any** permission result as its own: notifications, microphone,
or the SMS permission asked through permission_handler. It then replies again
to the last call it handled, which has already been answered, and the activity
dies with

```
java.lang.IllegalStateException: Reply already submitted
```

The patched test handles a result only while this plugin has a request of its
own open and the request code matches.

Drop this copy and go back to the hosted package once a release fixes it.
