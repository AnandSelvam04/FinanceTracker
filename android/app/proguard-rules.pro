# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Sign In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.firebase.** { *; }

# Sqflite
-keep class com.tekartik.sqflite.** { *; }

# flutter_local_notifications (Gson-serialized scheduled notifications)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
# Gson reads generic type information (TypeToken) at runtime. R8 strips it
# unless told otherwise, and scheduling then fails with "Missing type
# parameter" -- swallowed by the app, so reminders silently never arm.
# Rules from Gson's own Android ProGuard example.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken

# General
-dontwarn io.flutter.embedding.**
-ignorewarnings
