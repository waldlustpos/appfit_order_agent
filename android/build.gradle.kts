allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // 모든 모듈(third-party Flutter 플러그인 포함)에서 가져오는 kotlin-stdlib을
    // settings.gradle.kts에서 선언한 Kotlin Gradle Plugin 버전과 동일하게 강제.
    // 이를 통해 "Module was compiled with an incompatible version of Kotlin"
    // 메타데이터 미스매치 메시지를 제거한다.
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin" &&
                requested.name.startsWith("kotlin-stdlib")
            ) {
                useVersion("2.1.0")
            }
        }
    }
}

// 모든 서브프로젝트의 javac 옵션을 Java 11로 통일하여
// "source/target value 8 is obsolete" 경고를 제거.
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension>("android") {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
