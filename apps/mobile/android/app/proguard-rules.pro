# Conservative R8 keep rules for Moneymind release builds.
# Add to this file when a reflectively-used class gets stripped (look for
# ClassNotFoundException / NoSuchMethodException in logcat after release).

# Flutter engine + plugin channels
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core — Flutter's deferred-components shim references these even when unused
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Firebase + Google Play Services (reflective serialization in Firestore models)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# SQLCipher (Drift cipher backend)
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }
-dontwarn net.sqlcipher.**

# RevenueCat
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# flutter_local_notifications — instantiates BroadcastReceivers reflectively
-keep class com.dexterous.** { *; }

# Kotlin metadata used by reflection-based libs
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata { *; }
