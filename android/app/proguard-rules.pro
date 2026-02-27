# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep WaldNDK class and its native methods
-keep,includedescriptorclasses class com.waldget.stamp.** {
    <fields>;
    <methods>;
}

# Flutter 관련 규칙
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# AndroidX Window 라이브러리 (R8 호환성)
-dontwarn androidx.window.**
-keep class androidx.window.** { *; }
-keep class androidx.window.extensions.** { *; }
-keep class androidx.window.sidecar.** { *; }

# Kotlin 관련
-dontwarn kotlin.**
-dontwarn kotlinx.**
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

# BouncyCastle (암호화 라이브러리)
-dontwarn org.bouncycastle.**
-keep class org.bouncycastle.** { *; }

# Volley
-keep class com.android.volley.** { *; }

# Sunmi Printer
-keep class com.sunmi.** { *; }
-keep class woyou.aidlservice.jiuiv5.** { *; }

# ZXing (QR 코드)
-keep class com.google.zxing.** { *; }
-keep class com.journeyapps.** { *; }

# POSBANK
-keep class com.posbank.** { *; }

# 리플렉션 관련 경고 무시
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.codehaus.**

# 일반 라인 번호 보존 (디버깅용)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Enum 클래스의 values(), valueOf() 메서드 보존 (R8/EnumMap 크래시 방지)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# flutter_secure_storage (R8 호환성)
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# connectivity_plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# device_info_plus
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# package_info_plus
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# Firebase (필요한 경우)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AutoReplyPrint (라벨 프린터)
-keep class com.caysn.autoreplyprint.** { *; }
-dontwarn com.caysn.autoreplyprint.**
-keep class com.lvrenyang.** { *; }
-dontwarn com.lvrenyang.**

# JNA (Java Native Access)
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-dontwarn com.sun.jna.**
