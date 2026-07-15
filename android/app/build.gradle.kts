import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Absent on a fresh clone and on CI — the file is
// gitignored, so every value below has to stay optional at configuration time.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Personal sideloaded builds can keep the SMS Inbox feature; Play builds cannot.
// See src/release/AndroidManifest.xml for why this is a manifest-merge override
// rather than a plain edit to src/main.
val keepSmsPermission = System.getenv("FLOWFI_SMS") == "1"
if (keepSmsPermission) {
    logger.lifecycle("FLOWFI_SMS=1: keeping READ_SMS — this build is NOT valid for a Play Store upload.")
}

android {
    namespace = "com.example.finance_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Play builds must not ship READ_SMS (see src/release/AndroidManifest.xml).
    // Stripping is the default so that forgetting the flag yields a compliant
    // upload rather than a rejected one; FLOWFI_SMS=1 opts a personal sideloaded
    // build back in by swapping the overlay for an empty one.
    if (keepSmsPermission) {
        sourceSets.getByName("release").manifest.srcFile("src/releaseSms/AndroidManifest.xml")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // NOT PLAY-STORE PUBLISHABLE AS-IS: Google Play rejects any `com.example.*`
        // applicationId. Renaming this is a coordinated change — the id is also
        // baked into google-services.json, and the google-services plugin fails the
        // build ("No matching client found for package name") if the two disagree.
        // Do not edit this line alone; follow PLAY_STORE.md > "Renaming the
        // application ID", which sequences the Firebase Console registration first.
        applicationId = "com.example.finance_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only declared when key.properties exists. The previous unconditional
        // `keystoreProperties["keyAlias"] as String` threw on a null cast during
        // Gradle's configuration phase, which fails *every* variant (debug and
        // profile included) on any machine without the keystore, not just release.
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Null without key.properties. Deliberately no debug-signing fallback:
            // a debug-signed artifact looks valid and would be caught only on
            // upload, whereas the task guard below fails fast with a real reason.
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            // Resource shrinking strips Crashlytics' build-ID resource (it's only
            // read via native/reflection lookup, so the shrinker sees it as unused),
            // which makes FirebaseInitProvider throw and crashes the app on launch.
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by flutter_local_notifications for Java 8+ API desugaring on API < 26.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Fail with an actionable message instead of silently emitting an unsigned
// (uninstallable, un-uploadable) artifact. Keyed off the requested task names so
// that debug and profile builds still work without the keystore present.
if (!hasKeystore && gradle.startParameter.taskNames.any { it.contains("Release") }) {
    throw GradleException(
        "Release signing requires android/key.properties, which is gitignored and " +
            "absent. See PLAY_STORE.md > 'Keystore management' to create it."
    )
}

// Gradle 9 removed Groovy from the runtime classpath, which breaks the
// Crashlytics plugin's mapping-file upload task (it still calls into
// groovy.util.XmlSlurper). Crash symbolication isn't needed for a
// personal-use app, so skip that task instead of chasing plugin versions.
tasks.configureEach {
    if (name.startsWith("uploadCrashlyticsMappingFile")) {
        enabled = false
    }
}
