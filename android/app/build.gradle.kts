
import java.util.Properties

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")

if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use {
        localProperties.load(it)
    }
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.campresso.app.campresso"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ✅ Make Java match Kotlin (17)
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // ✅ Required for flutter_local_notifications (and other libs)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // ✅ Kotlin target 17
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.campresso.app.campresso"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName


        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            localProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
    }

    buildTypes {
        getByName("release") {
            // ✅ temporary signing for testing
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}