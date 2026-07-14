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

# General
-dontwarn io.flutter.embedding.**
-ignorewarnings
