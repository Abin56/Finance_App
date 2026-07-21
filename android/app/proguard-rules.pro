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
