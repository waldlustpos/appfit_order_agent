#!/bin/bash

###############################################################################
# Flutter Release 빌드 후 Lightsail(EC2) 서버에 APK 업로드 및
# OTA version JSON 갱신 스크립트
###############################################################################

# 단일 빌드(단일 패키지 co.kr.waldlust.order.receive.appfit)가 한국/일본을
# 모두 서빙한다. 서버(live/japanLive)는 앱 로그인 화면에서 런타임 선택되므로
# 빌드 인자가 없다. OTA 채널은 _release 하나만 사용한다.

# 0) 사용자 정의 변수
PROJECT_PATH="."
PEM_KEY_PATH="$HOME/.ssh/LightsailDefaultKey-ap-northeast-3.pem"
REMOTE_USER="ec2-user"
REMOTE_HOST="52.78.172.188"
REMOTE_DIR="/var/www/docs/waldpay_html"

###############################################################################
# !!! 경고: 레거시 무접미 채널(appfit_order_agent.apk / appfit_order_agent_version.json)
#     은 동결(FROZEN)이다. 이 스크립트는 절대 그 이름으로 업로드하지 않는다.
#     구 패키지(co.kr.waldlust.order.receive)로 설치된 일본 매장 1곳이 해당
#     채널을 폴링 중이라, .appfit 패키지 APK 를 그 이름으로 올리면 패키지
#     불일치로 설치가 실패한다. 신규 패키지로 수동 재설치되기 전까지 유지.
###############################################################################
APK_NAME="appfit_order_agent_release.apk"
VERSION_JSON_NAME="appfit_order_agent_release_version.json"

# 1) 프로젝트 디렉토리로 이동
echo "==== 1) Move to Flutter project path ===="
cd "$PROJECT_PATH" || {
  echo "[오류] 프로젝트 디렉토리($PROJECT_PATH)로 이동 실패!"
  exit 1
}

# 2) Flutter Release 빌드 (단일 빌드 — 변형 주입 없음)
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

echo ".env 주입하여 빌드..."
# --target-platform: x86_64 AOT 컴파일을 건너뛴다(빌드 시간 단축). 실제 패키징
# 차단의 정본은 android/app/build.gradle.kts 의 release ndk.abiFilters 다 —
# Flutter Gradle 플러그인이 서드파티 AAR 용 abiFilters 를 3종 ABI 로 고정해서
# 이 플래그만으로는 x86_64 네이티브가 안 빠지기 때문.
# armeabi-v7a 는 필수 — D2s_KDS 가 32비트 전용(zygote32)이다. docs/BUILD.md 참조.
flutter build apk --release --target-platform android-arm,android-arm64 --dart-define-from-file=.env
if [ $? -ne 0 ]; then
  echo "[오류] Flutter 빌드 실패!"
  exit 1
fi

# 빌드된 apk 기본 경로 (flavor 미사용 → 단일 app-release.apk)
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
scp -o StrictHostKeyChecking=no -i "$PEM_KEY_PATH" version.json "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$VERSION_JSON_NAME"
if [ $? -ne 0 ]; then
  echo "[오류] version JSON 업로드 실패!"
  rm -f version.json
  exit 1
fi
rm -f version.json
echo "✅ version JSON 업로드 완료: version = $BUILD_NUMBER"

# 7) 로컬 아카이브 보관 + 노트 기록 + 폴더 열기 (배포 성공분만 보관)
echo "==== 7) Archive APK to local Project Files ===="
bash "$PROJECT_PATH/archive_apk.sh" "$PROJECT_PATH/$APK_NAME"

echo "###############################################################################"
echo "[완료] $APK_NAME 업로드 완료!"
echo "서버 경로: $REMOTE_HOST:$REMOTE_DIR/$APK_NAME"
echo "OTA 업데이트 URL: http://waldpay.kokonutstamp2.com/$APK_NAME"
echo "버전 JSON URL: http://waldpay.kokonutstamp2.com/$VERSION_JSON_NAME (version=$BUILD_NUMBER)"
echo "###############################################################################"
