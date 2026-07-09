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
echo "3. Android APK 빌드 중..."
flutter build apk --release --dart-define-from-file=.env

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
