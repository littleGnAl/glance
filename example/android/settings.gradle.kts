import java.util.Properties // Required for Properties class

pluginManagement {
    val flutterSdkPath = run {
        val properties = Properties()
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }
        val path = properties.getProperty("flutter.sdk")
        checkNotNull(path) {
            """
            flutter.sdk not set in local.properties.
            Please create a file named `local.properties` in the `example/android` directory and add a line like:
            flutter.sdk=/path/to/your/flutter/sdk
            """.trimIndent()
        }
        path
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.2.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}

include(":app")
