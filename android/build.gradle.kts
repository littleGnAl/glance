group = "com.littlegnal.glance"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    if (project.hasProperty("android") && project.android.hasProperty("namespace")) {
        namespace = "com.littlegnal.glance"
    }

    compileSdk = 35

    externalNativeBuild {
        cmake {
            path = "../src/CMakeLists.txt"
            // version = "3.10.2" // Keep commented as in original
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
        getByName("test").java.srcDirs("src/test/kotlin")
    }

    defaultConfig {
        minSdk = 21

        externalNativeBuild {
            cmake {
                arguments.add("-DANDROID_STL=c++_static")
            }
        }
    }

    testOptions {
        unitTests.all {
            useJUnitPlatform()

            testLogging {
               events("passed", "skipped", "failed", "standardOut", "standardError")
               outputs.upToDateWhen { false }
               showStandardStreams = true
            }
        }
    }
}

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
