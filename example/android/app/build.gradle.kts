plugins {
    id("com.android.application")
    kotlin("android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.littlegnal.glance_example"

    // Assuming 'flutter' is an extension object readily available.
    // If not, this might need adjustment to:
    // val flutterExtension = extensions.getByType(dev.flutter.gradle.FlutterExtension::class.java)
    // compileSdk = flutterExtension.compileSdkVersion
    // ndkVersion = flutterExtension.ndkVersion
    // Or, if flutter is a convention object:
    // val flutterPlugin = convention.getPlugin(dev.flutter.gradle.FlutterPlugin::class.java)
    // compileSdk = flutterPlugin.flutterExtension.compileSdkVersion
    // etc.
    // For now, trying direct access as it's often configured this way by the Flutter plugin.
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.littlegnal.glance_example"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source("../..")
}
