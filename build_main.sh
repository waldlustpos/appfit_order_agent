#!/bin/bash

# 프로젝트 정보 추출
PROJECT_NAME=$(grep "^name:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
VERSION=$(grep "^version:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
BUILD_DATE=$(date +%Y%m%d)

echo "=== 코코넛 주문 접수 앱 빌드 시작 ==="
echo "패키지명: co.kr.waldlust.order.receive"
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

# Android 빌드 (flavor 제거, 환경 변수 주입 추가)
echo "3. Android APK 빌드 중..."
flutter build apk --release --dart-define-from-file=.env

# 빌드 결과 파일명 변경
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

echo "추가 작업: 출력 폴더 여는 중..."
open build/app/outputs/flutter-apk/
