#!/bin/bash

echo "=== 코코넛 주문 접수 앱 빌드 시작 ==="
echo "패키지명: co.kr.waldlust.order.receive"
echo "앱 이름: 코코넛 주문 접수"
echo "버전: pubspec.yaml 참조"
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

echo ""
echo "=== APK 빌드 완료 ==="
echo "APK 파일 위치: build/app/outputs/flutter-apk/app-release.apk"
echo "설치 명령어: adb install build/app/outputs/flutter-apk/app-release.apk"

echo "Build completed!"
echo "APK location: build/app/outputs/flutter-apk/app-release.apk"

echo "추가 작업: 출력 폴더 여는 중..."
open build/app/outputs/flutter-apk/
