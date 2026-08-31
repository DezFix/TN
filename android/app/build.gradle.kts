plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ONE keystore everywhere (local AND CI) — the published global signature:
//   1. android/key.properties  (gitignored; the preferred local setup)
//        TN_STORE_FILE=/abs/path/to/tn-release.jks
//        TN_STORE_PASS=...
//        TN_KEY_ALIAS=...
//        TN_KEY_PASS=...
//   2. CI secrets via env vars of the same names.
// If neither is present the build falls back to the DEBUG key on purpose
// (so `flutter build apk` never hard-fails), but prints a loud warning —
// such an APK cannot install over the published app, which is exactly what
// produced the recurring "package corrupted" update reports.
import java.util.Properties

val tnKeyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun tnSigningProp(name: String): String? =
    tnKeyProps.getProperty(name) ?: System.getenv(name)

android {
    namespace = "app.tn.tn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.tn.tn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storePath = tnSigningProp("TN_STORE_FILE")
            val storePass = tnSigningProp("TN_STORE_PASS")
            val keyAlias = tnSigningProp("TN_KEY_ALIAS")
            val keyPass = tnSigningProp("TN_KEY_PASS")
            if (storePath != null && storePass != null && keyAlias != null && keyPass != null) {
                storeFile = file(storePath)
                storePassword = storePass
                this.keyAlias = keyAlias
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            val signingConfigured = tnSigningProp("TN_STORE_FILE") != null &&
                    tnSigningProp("TN_STORE_PASS") != null &&
                    tnSigningProp("TN_KEY_ALIAS") != null &&
                    tnSigningProp("TN_KEY_PASS") != null
            signingConfig = if (signingConfigured) {
                signingConfigs.getByName("release")
            } else {
                println("WARNING: TN release signing not configured (android/key.properties or TN_* env vars).")
                println("WARNING: This APK is signed with the DEBUG key — it will NOT install over the published app.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
