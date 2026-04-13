import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// Upload keystore: android/key.properties (see key.properties.example) or CI env vars below.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun keystoreProp(name: String, env: String): String? =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: System.getenv(env)?.takeIf { it.isNotBlank() }

val resolvedStorePath = keystoreProp("storeFile", "WOLEH_KEYSTORE_PATH")
val resolvedStorePassword = keystoreProp("storePassword", "WOLEH_KEYSTORE_PASSWORD")
val resolvedKeyAlias = keystoreProp("keyAlias", "WOLEH_KEY_ALIAS")
val resolvedKeyPassword = keystoreProp("keyPassword", "WOLEH_KEY_PASSWORD")

val releaseSigningEnabled =
    listOf(resolvedStorePath, resolvedStorePassword, resolvedKeyAlias, resolvedKeyPassword).all { it != null }

val resolvedStoreFile = resolvedStorePath?.let { path ->
    val f = rootProject.file(path)
    if (!f.isFile) {
        error(
            "Release keystore not found: ${f.absolutePath}. " +
                "Fix storeFile in key.properties or WOLEH_KEYSTORE_PATH.",
        )
    }
    f
}

android {
    namespace = "odm.clarity.woleh_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "odm.clarity.woleh_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningEnabled) {
            create("release") {
                storeFile = resolvedStoreFile!!
                storePassword = resolvedStorePassword!!
                keyAlias = resolvedKeyAlias!!
                keyPassword = resolvedKeyPassword!!
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (releaseSigningEnabled) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug").also {
                        logger.warn(
                            "Release APK/AAB uses debug signing. " +
                                "Add android/key.properties (see key.properties.example) " +
                                "or set WOLEH_KEYSTORE_PATH, WOLEH_KEYSTORE_PASSWORD, WOLEH_KEY_ALIAS, WOLEH_KEY_PASSWORD.",
                        )
                    }
                }
        }
    }
}

flutter {
    source = "../.."
}
