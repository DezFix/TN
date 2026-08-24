plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.tn.tn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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

    // Stable release signature. On CI the keystore arrives via secrets
    // (TN_KEYSTORE_B64/TN_STORE_PASS/TN_KEY_PASS/TN_KEY_ALIAS); locally, when
    // the env vars are absent, builds fall back to the debug key.
    signingConfigs {
        create("release") {
            val storePath = System.getenv("TN_STORE_FILE")
            if (storePath != null) {
                storeFile = file(storePath)
                storePassword = System.getenv("TN_STORE_PASS")
                keyAlias = System.getenv("TN_KEY_ALIAS")
                keyPassword = System.getenv("TN_KEY_PASS")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("TN_STORE_FILE") != null) {
                signingConfigs.getByName("release")
            } else {
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
