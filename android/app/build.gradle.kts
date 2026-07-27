import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties:
//   storeFile=/path/to/keystore.jks
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
// When the file is absent (a fork, or a checkout without it), the release
// build falls back to the debug key so `flutter build apk --release` still
// works.
//
// NOTE: in this repository android/key.properties AND the keystore itself
// (android/app/finance-release.jks) are committed, with the passwords in
// plaintext, past the .gitignore rules that would normally exclude them. That
// is deliberate: this is a personal app distributed as an APK, and Google
// Drive's OAuth client is bound to the package name plus the signing
// certificate's SHA-1, so a stable key keeps Drive backup working across
// rebuilds (see docs/GOOGLE_DRIVE_SETUP.md, which publishes that SHA-1).
//
// Understand what it costs before copying this pattern: anyone with repo
// access can build an APK that Android accepts as an in-place update of an
// installed Finance Tracker — inheriting its private data directory — and one
// that Google accepts as this app. The key cannot be rotated for already
// installed copies. For anything published to Play, generate a key that stays
// out of version control and inject it from a CI secret instead.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.example.finance_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time on older APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.finance_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Proper release signing when key.properties exists; debug key
            // otherwise so test builds remain installable.
            signingConfig = if (hasReleaseKeystore)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
