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

# co.kr.waldlust.order.receive 패키지의 주요 클래스 및 메서드 보존
-keep class co.kr.waldlust.order.receive.NativeMethodHandler { *; }
-keep class co.kr.waldlust.order.receive.MainActivity {
    public void appendLogToFile(java.lang.String);
    public void appendLogsToFile(java.util.List);
    public boolean checkPermissions();
    public boolean checkAndRequestPermissions();
    public boolean hasAllFilesAccess();
    public void requestAllFilesAccess();
}
-keep class co.kr.waldlust.order.receive.overlay.OverlayHelper { *; }
-keep class co.kr.waldlust.order.receive.util.print.LabelPrinter { *; }
-keep class co.kr.waldlust.order.receive.util.print.SunmiPrintHelper { *; }
-keep class co.kr.waldlust.order.receive.OrderAgentService { *; }

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

# BIXOLON 공용 라이브러리 - G30(UPOS)이 물고 있다. XD5-40d 지원 종료 후에도 남는다.
# 실제 커버 대상은 두 개뿐이다 (com.bixolon.labelprinter 는 jar 와 함께 삭제됨):
#   com.bixolon.commonlib - libcommon jar. UPOS jar 24개 클래스가 참조.
#   com.bixolon.pdflib     - 우리 스텁. POSPrinterBaseService.validateDevice() 가
#                            참조하는데 그 catch (Exception) 은 NoClassDefFoundError 를
#                            못 잡는다 -> shrink 되면 G30 connect 경로에서 크래시.
# -dontwarn 도 별도로 load-bearing: UPOS jar 가 스텁에 없는 pdflib 멤버를 참조한다.
# 지우면 debug 는 멀쩡하고 release 에서만 G30 이 죽는다. 좁히려면 release 빌드 +
# G30 실기기 스모크를 먼저 통과시킬 것.
-keep class com.bixolon.** { *; }
-dontwarn com.bixolon.**

# BIXOLON UPOS SDK (G30) - jpos.* 는 JposEntry 가 클래스명 문자열로 리플렉션
# 인스턴스화한다 (ServiceInstanceFactory). keep 없이는 release 에서만 실패한다.
# mf.javax.xml.** 는 JAXP 클래스를 통째로 리로케이트한 shim(FactoryFinder 의
# DEFAULT_PROPERTY_NAME 폴백이 mf.org.apache.xerces.* 구현체를 Class.forName
# 문자열로 찾음) - jpos.xml 저장/로드가 물고 있어 -dontwarn 만으론 release 에서
# shrink 되어 ClassNotFoundException. 통째로 -keep.
-keep class com.bxl.** { *; }
-dontwarn com.bxl.**
-keep class jpos.** { *; }
-dontwarn jpos.**
-keep class mf.org.apache.** { *; }
-dontwarn mf.org.apache.**
-keep class mf.javax.xml.** { *; }
-dontwarn mf.javax.xml.**

# JNA (Java Native Access)
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# Sentry Replay - Jetpack Compose 미사용 프로젝트에서 참조 경고 무시
-dontwarn androidx.compose.runtime.internal.StabilityInferred
-dontwarn androidx.compose.ui.Modifier
-dontwarn androidx.compose.ui.geometry.Offset
-dontwarn androidx.compose.ui.geometry.OffsetKt
-dontwarn androidx.compose.ui.geometry.Rect
-dontwarn androidx.compose.ui.graphics.Color$Companion
-dontwarn androidx.compose.ui.graphics.Color
-dontwarn androidx.compose.ui.graphics.ColorKt
-dontwarn androidx.compose.ui.layout.LayoutCoordinates
-dontwarn androidx.compose.ui.layout.LayoutCoordinatesKt
-dontwarn androidx.compose.ui.layout.ModifierInfo
-dontwarn androidx.compose.ui.node.LayoutNode
-dontwarn androidx.compose.ui.node.NodeCoordinator
-dontwarn androidx.compose.ui.node.Owner
-dontwarn androidx.compose.ui.semantics.AccessibilityAction
-dontwarn androidx.compose.ui.semantics.SemanticsActions
-dontwarn androidx.compose.ui.semantics.SemanticsConfiguration
-dontwarn androidx.compose.ui.semantics.SemanticsConfigurationKt
-dontwarn androidx.compose.ui.semantics.SemanticsProperties
-dontwarn androidx.compose.ui.semantics.SemanticsPropertyKey
-dontwarn androidx.compose.ui.text.TextLayoutInput
-dontwarn androidx.compose.ui.text.TextLayoutResult
-dontwarn androidx.compose.ui.text.TextStyle
-dontwarn androidx.compose.ui.unit.IntSize
