import java.util.Properties
import com.android.build.api.artifact.SingleArtifact

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

android {
    namespace = "com.example.finance_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Distribution channel is an explicit build flavor, not an environment
    // variable. `--flavor` must be passed to every `flutter build`/`flutter
    // run` invocation once flavors are declared — Flutter refuses to guess
    // and lists the valid flavors instead, so it is no longer possible to
    // silently produce a build with the wrong SMS permission because a flag
    // was forgotten. See src/play/AndroidManifest.xml and
    // src/sideload/AndroidManifest.xml for what each flavor changes.
    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
            // Play Store artifact. READ_SMS is removed for every build type
            // of this flavor via src/play/AndroidManifest.xml — Google Play
            // restricts SMS permissions to default SMS handlers.
        }
        create("sideload") {
            dimension = "distribution"
            // Personal, non-Play artifact. Keeps READ_SMS (contributed by
            // src/main and by flutter_sms_inbox's own library manifest) via
            // the empty overlay at src/sideload/AndroidManifest.xml.
            // Never upload this flavor's output to Play.
        }
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

// Verifies the SMS build-configuration bug (READ_SMS silently missing from a
// build meant to have it, because a flag was forgotten) cannot recur silently.
// Reads each variant's actual MERGED manifest — the same file `aapt dump
// permissions` reflects — rather than trusting the source manifests, since
// the merge is exactly where the previous env-var mechanism went wrong.
// Wired to run automatically as part of every `assemble<Variant>` task.
androidComponents {
    onVariants { variant ->
        val expectReadSms = variant.flavorName == "sideload"
        val variantNameCapitalized = variant.name.replaceFirstChar { it.uppercase() }
        val manifestArtifact = variant.artifacts.get(SingleArtifact.MERGED_MANIFEST)

        val verifyTask = tasks.register("verifySmsPermission$variantNameCapitalized") {
            group = "verification"
            description = "Checks that the $variantNameCapitalized merged manifest has READ_SMS " +
                (if (expectReadSms) "present (sideload flavor)." else "absent (play flavor).")
            val manifestFileProperty = manifestArtifact
            inputs.file(manifestFileProperty)
            doLast {
                val manifestText = manifestFileProperty.get().asFile.readText()
                val hasReadSms = Regex("""android\.permission\.READ_SMS""").containsMatchIn(manifestText)
                if (hasReadSms != expectReadSms) {
                    throw GradleException(
                        "SMS permission check failed for variant '${variant.name}': expected " +
                            "READ_SMS to be ${if (expectReadSms) "PRESENT" else "ABSENT"} in the merged " +
                            "manifest, but it was ${if (hasReadSms) "present" else "absent"}. " +
                            "See android/app/build.gradle.kts productFlavors and " +
                            "src/play|sideload/AndroidManifest.xml."
                    )
                }
                logger.lifecycle(
                    "verifySmsPermission$variantNameCapitalized: READ_SMS is " +
                        "${if (hasReadSms) "present" else "absent"} as expected."
                )
            }
        }

        // Same guardrail as verifySmsPermission above, for the notification
        // listener service that backs the SMS Inbox feature's RCS-capture
        // path (see NotificationCaptureListenerService) — it carries the
        // same Play-policy risk as READ_SMS, so it must be excluded from the
        // play flavor's merged manifest just as reliably.
        val expectNotificationListener = variant.flavorName == "sideload"
        val verifyNotificationListenerTask =
            tasks.register("verifyNotificationListener$variantNameCapitalized") {
                group = "verification"
                description = "Checks that the $variantNameCapitalized merged manifest has the " +
                    "notification listener service " +
                    (if (expectNotificationListener) "present (sideload flavor)." else "absent (play flavor).")
                val manifestFileProperty = manifestArtifact
                inputs.file(manifestFileProperty)
                doLast {
                    val manifestText = manifestFileProperty.get().asFile.readText()
                    val hasService = Regex("""NotificationCaptureListenerService""")
                        .containsMatchIn(manifestText)
                    if (hasService != expectNotificationListener) {
                        throw GradleException(
                            "Notification listener check failed for variant '${variant.name}': " +
                                "expected NotificationCaptureListenerService to be " +
                                "${if (expectNotificationListener) "PRESENT" else "ABSENT"} in the merged " +
                                "manifest, but it was ${if (hasService) "present" else "absent"}. " +
                                "See android/app/build.gradle.kts productFlavors and " +
                                "src/play|sideload/AndroidManifest.xml."
                        )
                    }
                    logger.lifecycle(
                        "verifyNotificationListener$variantNameCapitalized: service is " +
                            "${if (hasService) "present" else "absent"} as expected."
                    )
                }
            }

        tasks.matching { it.name == "assemble$variantNameCapitalized" }.configureEach {
            finalizedBy(verifyTask, verifyNotificationListenerTask)
        }
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
