plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lemonade.mobile.chat.ai"
    compileSdk = flutter.compileSdkVersion
    // Pin NDK 27 — it's the first NDK that defaults to 16KB-aligned LOAD
    // segments on arm64-v8a / x86_64 .so output. Required for Google
    // Play's 16KB page size check (mandatory for Android 15+ devices,
    // enforced for new submissions and updates per Play policy).
    // Without this, anything we compile would still be 4KB aligned.
    // Plugin-supplied .so files still need to be aligned by their own
    // maintainers — see comments above the doctor task below for how
    // to diagnose stragglers.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // Pack .so files uncompressed and page-aligned so the OS can mmap them
    // directly — uncompressed JNI libs are the precondition for the 16KB
    // alignment check to even apply per-library.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = "upload"
            keyPassword = "password"
            storeFile = file("upload-keystore.jks")
            storePassword = "password"
        }
    }

    defaultConfig {
        applicationId = "com.lemonade.mobile.chat.ai"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
