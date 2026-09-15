# R8 keep rules for the release build.
#
# Debug builds do not minify, so nothing in this file affects `flutter run`.
# That is exactly why it was missing for so long: every test was a debug
# build, and the release APK died on launch on a real phone.
#
# THE CRASH THIS FIXES
#
#   java.lang.RuntimeException: Unable to get provider
#     androidx.startup.InitializationProvider
#   Caused by: Failed to create an instance of androidx.work.impl.WorkDatabase
#
# The chain is: google_mobile_ads -> play-services-ads-api -> androidx.work
# -> Room. Room does not construct its database class directly; it looks up
# the *generated* `WorkDatabase_Impl` by name and instantiates it by
# reflection. Nothing in the compiled code ever names that class, so R8 sees
# it as unreachable and removes it — and the failure lands in a ContentProvider
# during `handleBindApplication`, which is before Flutter starts. There is no
# Dart stack, no `main()`, and nothing the app can catch: the process is dead
# before any of our code runs.
#
# Reflection is invisible to a shrinker. Every rule below exists because
# something looks a class up by name at runtime.

# --- Room ------------------------------------------------------------------
# Keeps every generated `_Impl` and its no-argument constructor. `extends`
# matches transitively, so this covers WorkDatabase_Impl without naming an
# androidx internal that could be renamed in a future version.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-dontwarn androidx.room.paging.**

# --- WorkManager -----------------------------------------------------------
# Workers are also constructed by name, from a string in the database. A
# stripped Worker fails later and more quietly than the database does.
-keep class * extends androidx.work.ListenableWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }

# --- androidx.startup ------------------------------------------------------
# Initializers are named in the manifest as meta-data strings, so the only
# reference to them is text R8 cannot follow.
-keep class * implements androidx.startup.Initializer { <init>(); }

# --- Google Mobile Ads -----------------------------------------------------
# The SDK ships its own consumer rules; this only silences warnings about
# optional integrations (mediation adapters) that are not in this build.
-dontwarn com.google.android.gms.ads.**

# --- Play Games Services ---------------------------------------------------
-dontwarn com.google.android.gms.games.**
