#!/bin/bash

# 단일 빌드(단일 패키지 co.kr.waldlust.order.receive.appfit)가 한국/일본을
# 모두 서빙한다. 서버(live/japanLive)는 앱 로그인 화면에서 런타임 선택되므로
# 빌드 인자가 없다.

# 프로젝트 정보 추출
PROJECT_NAME=$(grep "^name:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
VERSION=$(grep "^version:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
BUILD_DATE=$(date +%Y%m%d)

APP_ID="co.kr.waldlust.order.receive.appfit"

echo "=== Appfit 주문 접수 앱 빌드 시작 ==="
echo "패키지명: $APP_ID"
echo "앱 이름: $PROJECT_NAME"
echo "버전: $VERSION"
echo "빌드 날짜: $BUILD_DATE"
echo ""

# Flutter clean
echo "1. Flutter clean 실행 중..."
flutter clean

# Flutter pub get
echo "2. Flutter pub get 실행 중..."
flutter pub get

# Android 빌드 (단일 빌드 — 변형 주입 없음)
# --target-platform: x86_64 AOT 컴파일을 건너뛴다(빌드 시간 단축). 실제 패키징
# 차단의 정본은 android/app/build.gradle.kts 의 release ndk.abiFilters 다 —
# Flutter Gradle 플러그인이 서드파티 AAR 용 abiFilters 를 3종 ABI 로 고정해서
# 이 플래그만으로는 x86_64 네이티브가 안 빠지기 때문.
# armeabi-v7a 는 필수 — D2s_KDS 가 32비트 전용(zygote32)이다. docs/BUILD.md 참조.
echo "3. Android APK 빌드 중..."
flutter build apk --release --target-platform android-arm,android-arm64 --dart-define-from-file=.env

# 빌드 결과 파일명 변경 (flavor 미사용 → 단일 app-release.apk)
ORIGINAL_APK="build/app/outputs/flutter-apk/app-release.apk"
NEW_APK_NAME="${PROJECT_NAME}_v${VERSION}_${BUILD_DATE}.apk"
NEW_APK_PATH="build/app/outputs/flutter-apk/${NEW_APK_NAME}"

if [ -f "$ORIGINAL_APK" ]; then
    echo ""
    echo "=== APK 파일명 변경 중... ==="
    mv "$ORIGINAL_APK" "$NEW_APK_PATH"
    echo "변경 완료: $NEW_APK_NAME"
else
    echo ""
    echo "!!! 경고: 빌드 결과물을 찾을 수 없습니다 ($ORIGINAL_APK) !!!"
    if [ ! -f "$NEW_APK_PATH" ]; then
        exit 1
    fi
fi

echo ""
echo "=== APK 빌드 완료 ==="
echo "APK 파일 위치: $NEW_APK_PATH"
echo "설치 명령어: adb install $NEW_APK_PATH"

echo "Build completed!"
echo "APK location: $NEW_APK_PATH"

# 로컬 아카이브 보관 + 노트 기록 + 폴더 열기 (아카이브 버전 폴더가 열린다)
bash ./archive_apk.sh "$NEW_APK_PATH"
