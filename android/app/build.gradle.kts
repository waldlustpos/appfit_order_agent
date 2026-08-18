import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin은 Android/Kotlin 플러그인 뒤에 적용해야 함.
    id("dev.flutter.flutter-gradle-plugin")
}

// pubspec.yaml -> Flutter CLI가 local.properties에 versionCode/versionName 주입
val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

val flutterVersionCode: Int = (localProperties.getProperty("flutter.versionCode") ?: "1").toInt()
val flutterVersionName: String = localProperties.getProperty("flutter.versionName") ?: "1.0"

// 릴리즈 키스토어 설정
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "co.kr.waldlust.order.receive"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // 단일 빌드가 한국/일본을 모두 서빙한다. 서버(live/japanLive)는 앱
        // 로그인 화면에서 런타임 선택하며, applicationId 는 국가 무관하게
        // .appfit 하나로 고정한다.
        // namespace(co.kr.waldlust.order.receive)는 R클래스/매니페스트 병합용이라
        // applicationId 와 달라도 무방하므로 그대로 둔다.
        applicationId = "co.kr.waldlust.order.receive.appfit"
        versionCode = flutterVersionCode
        versionName = flutterVersionName

        // Android 7 (API 24) 이상 지원
        minSdk = 24
        targetSdk = 35
    }

    // 2-티어 아티팩트 모델. 같은 코드·같은 버전이고 OS 셸 아이덴티티(applicationId,
    // 런처 label/icon)만 다르다. 브랜드 로직은 전부 런타임(BrandRegistry) 정본이며
    // 플레이버는 절대 로직을 가르지 않는다 (lib/config/build_brand.dart 참조).
    //
    // WARNING: 플레이버가 있는 프로젝트는 --flavor 없는 flutter build 가 실패한다.
    // 모든 빌드 스크립트와 .vscode/launch.json 에 --flavor 를 명시해야 한다.
    // Android 는 --flavor <slug> 와 --dart-define=APPFIT_BRAND=<slug> 를 반드시
    // 함께 넘긴다. 어긋나면 매머드 패키지가 공통 OTA 채널을 보게 되고, 받은 APK 는
    // 패키지 불일치로 설치가 실패한다.
    flavorDimensions += "brand"
    productFlavors {
        // Tier 0 — 공통 아티팩트. suffix 없음 = 기존 함대의 applicationId 불변.
        create("common") {
            dimension = "brand"
        }
        // Tier 1 — 매머드커피 전용. 별도 Sunmi App Store 리스팅이 필요해
        // 패키지를 분리한다: 리스팅은 패키지당 1개인데 모든 Sunmi 매장이 공통
        // 리스팅에서 설치하므로, 같은 패키지로는 "매머드 매장만 매머드 아이콘"을
        // 보장할 수 없다 (런처 아이콘은 앱 실행 전에 보여 런타임 게이팅 불가).
        create("mammoth") {
            dimension = "brand"
            applicationIdSuffix = ".mammoth"
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            storeFile = if (storeFilePath != null) file(storeFilePath) else null
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")

            // Drop x86_64 (emulator-only; no fleet device is x86). The Flutter Gradle
            // plugin pins abiFilters to [armeabi-v7a, arm64-v8a, x86_64] for every
            // build type regardless of --target-platform, so third-party AAR natives
            // (autoreplyprint, sentry, jna) would otherwise still smuggle in their
            // x86_64 copies. Clear and re-declare: measured -25 MiB.
            //
            // DO NOT drop armeabi-v7a. D2s_KDS is 32-bit ONLY - verified on device:
            //   D2s_KDS_STGL  Android 11  rk356x  ro.zygote=zygote32
            //                 ro.product.cpu.abilist=armeabi-v7a,armeabi
            //                 ro.product.cpu.abilist64=<empty>
            // RK3566 is a 64-bit Cortex-A55 part, but SUNMI ships a 32-bit Android
            // userspace on it, so the SoC datasheet does not tell you this - only
            // `adb shell getprop ro.product.cpu.abilist64` does. An arm64-only APK
            // fails on it with INSTALL_FAILED_NO_MATCHING_ABIS (empirically confirmed).
            // The other fleet devices are 64-bit (D3 MINI, T2mini_s: zygote64_32).
            //
            // Debug is intentionally left alone so x86_64 emulators keep working.
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a"))
            }
        }
    }

    packaging {
        jniLibs {
            // Compress the .so files. AGP 8 defaults this to false, which stores them
            // uncompressed so they can be mmap'd straight out of the APK - a good
            // trade for Play Store delta updates, but we ship a whole APK over store
            // wifi via our own OTA channel, so download size is what actually hurts.
            //
            // Measured on D3 MINI: APK 31.87 -> 18.75 MiB (native 23.30 -> 10.22).
            // Cost is ~10 MiB more on-device storage (libs get extracted at install).
            // Cold start did NOT regress - 825ms uncompressed vs 690ms compressed,
            // 3-run average.
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf(
                // JNA bundles jnidispatch for every host OS it supports. Android loads
                // it from lib/<abi>/libjnidispatch.so via System.loadLibrary, so the
                // AIX/Windows/macOS copies are dead weight (1.7 MiB).
                "com/sun/jna/aix-*/**",
                "com/sun/jna/darwin*/**",
                "com/sun/jna/win32-*/**",
                "com/sun/jna/linux-*/**",
                "com/sun/jna/freebsd-*/**",
                "com/sun/jna/openbsd-*/**",
                "com/sun/jna/sunos-*/**",
                // autoreplyprint.aar ships its .java sources; protobuf/firestore ship
                // .proto descriptors. Neither is read at runtime.
                "**/*.java",
                "**/*.proto",
            )
        }
    }
}

flutter {
    source = "../.."
}

// 우리 앱 모듈의 javac에 -Xlint:-options 추가 (third-party 플러그인의 obsolete 경고 무관 안전장치)
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.addAll(listOf("-Xlint:-options"))
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    implementation("com.android.volley:volley:1.2.1")
    implementation("com.sunmi:printerlibrary:1.0.23")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
    implementation("androidx.cardview:cardview:1.0.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(files("libs/autoreplyprint.aar"))
}
