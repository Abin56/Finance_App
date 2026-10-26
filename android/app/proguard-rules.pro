# Firebase / Firestore / Auth / Crashlytics use reflection for model (de)serialization.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# permission_handler and flutter_sms_inbox register Android plugin classes via
# reflection; R8 stripping them in release causes MissingPluginException at
# runtime (swallowed by AsyncValue.guard), which looks like a dead button.
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.juliusgithaiga.flutter_sms_inbox.** { *; }

# google_mlkit_text_recognition references optional script-specific recognizers
# (Chinese/Devanagari/Japanese/Korean) that are not bundled; only Latin is used.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# WorkManager (SmsScanWorker) builds its Room database by reflective class-name
# lookup; R8 stripping WorkDatabase_Impl crashes the app at startup in release.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
