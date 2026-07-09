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
