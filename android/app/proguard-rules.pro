# ════════════════════════════════════════════════════════════════
#  BLE Explorer — ProGuard / R8 rules
# ════════════════════════════════════════════════════════════════

# ── Flutter engine ───────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }
-dontwarn io.flutter.**

# ── Kotlin / Coroutines ──────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── flutter_blue_plus ────────────────────────────────────────────
-keep class com.boskokg.flutter_blue_plus.** { *; }
-dontwarn com.boskokg.flutter_blue_plus.**

# ── permission_handler ───────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── share_plus ───────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# ── path_provider ────────────────────────────────────────────────
-keep class io.flutter.plugins.pathprovider.** { *; }

# ── Apache POI / Excel (used by the excel package) ───────────────
-keep class org.apache.poi.** { *; }
-keep class org.openxmlformats.** { *; }
-dontwarn org.apache.poi.**
-dontwarn org.openxmlformats.**

# ── Suppress common third-party warnings ─────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.slf4j.**
-dontwarn okhttp3.**
-dontwarn okio.**

# ── Keep BuildConfig & R classes ─────────────────────────────────
-keepclassmembers class **.R$* {
    public static <fields>;
}

# ── Keep Serializable / Parcelable ───────────────────────────────
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── Keep native methods ───────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ── Preserve line numbers in stack traces for debugging ──────────
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
