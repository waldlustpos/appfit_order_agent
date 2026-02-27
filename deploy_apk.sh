#!/bin/bash

###############################################################################
# Flutter Release 빌드 후 Lightsail(EC2) 서버에 APK 업로드 및
# Firebase Remote Config 자동 업데이트 스크립트
###############################################################################

# 0) 사용자 정의 변수
PPROJECT_PATH="."
PEM_KEY_PATH="$HOME/.ssh/LightsailDefaultKey-ap-northeast-3.pem"
REMOTE_USER="ec2-user"
REMOTE_HOST="52.78.172.188"
REMOTE_DIR="/var/www/docs/waldpay_html"
APK_NAME="appfit_order_agent.apk"

# 1) 프로젝트 디렉토리로 이동
echo "==== 1) Move to Flutter project path ===="
cd "$PROJECT_PATH" || {
  echo "[오류] 프로젝트 디렉토리($PROJECT_PATH)로 이동 실패!"
  exit 1
}

# 2) Flutter Release 빌드 (flavor 제거)
# 2) Flutter Release 빌드 (flavor 제거)
echo "==== 2) Flutter build apk --release ===="

# .env 파일에서 AES Key 읽기
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi

if [ -z "$APPFIT_AES_KEY" ]; then
  echo "[경고] .env 파일이나 환경변수에서 APPFIT_AES_KEY를 찾을 수 없습니다."
  echo "빌드가 실패하거나 앱 실행 시 오류가 발생할 수 있습니다."
  # 필요 시 exit 1 로 중단 가능
fi

echo "APPFIT_AES_KEY 주입하여 빌드..."
flutter build apk --release --dart-define=APPFIT_AES_KEY="$APPFIT_AES_KEY"
if [ $? -ne 0 ]; then
  echo "[오류] Flutter 빌드 실패!"
  exit 1
fi

# 빌드된 apk 기본 경로
BUILT_APK="$PROJECT_PATH/build/app/outputs/flutter-apk/app-release.apk"

# 3) 빌드된 apk 이름 변경
echo "==== 3) Rename app-release.apk -> $APK_NAME ===="
if [ ! -f "$BUILT_APK" ]; then
  echo "[오류] 빌드 산출물(app-release.apk) 없음: $BUILT_APK"
  exit 1
fi

mv "$BUILT_APK" "$PROJECT_PATH/$APK_NAME"
if [ ! -f "$PROJECT_PATH/$APK_NAME" ]; then
  echo "[오류] 이름 변경 실패! $PROJECT_PATH/$APK_NAME 확인 요망."
  exit 1
fi

# 4) scp 명령어로 서버에 업로드
echo "==== 4) Upload to Lightsail(EC2) server via SCP ===="
scp -i "$PEM_KEY_PATH" "$PROJECT_PATH/$APK_NAME" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
if [ $? -ne 0 ]; then
  echo "[오류] scp 업로드 실패!"
  exit 1
fi

# 5) pubspec.yaml에서 빌드 번호 추출
echo "==== 5) Extract build number from pubspec.yaml ===="
BUILD_NUMBER=$(grep -E "^version:" pubspec.yaml | sed 's/.*+\([0-9]*\).*/\1/')
if [ -z "$BUILD_NUMBER" ]; then
  echo "[오류] pubspec.yaml에서 빌드 번호를 찾을 수 없습니다!"
  exit 1
fi
echo "빌드 번호: $BUILD_NUMBER"

# 6) version JSON 생성 및 서버 업로드
echo "==== 6) Upload version JSON to server ===="
VERSION_JSON="{\"version\": $BUILD_NUMBER}"
echo "$VERSION_JSON" > version.json
scp -o StrictHostKeyChecking=no -i "$PEM_KEY_PATH" version.json "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/kokonut_version.json"
if [ $? -ne 0 ]; then
  echo "[오류] version JSON 업로드 실패!"
  rm -f version.json
  exit 1
fi
rm -f version.json
echo "✅ version JSON 업로드 완료: version = $BUILD_NUMBER"

echo "###############################################################################"
echo "[완료] $APK_NAME 업로드 완료!"
echo "서버 경로: $REMOTE_HOST:$REMOTE_DIR/$APK_NAME"
echo "OTA 업데이트 URL: http://waldpay.kokonutstamp2.com/$APK_NAME"
echo "버전 JSON URL: http://waldpay.kokonutstamp2.com/kokonut_version.json (version=$BUILD_NUMBER)"
echo "###############################################################################"
