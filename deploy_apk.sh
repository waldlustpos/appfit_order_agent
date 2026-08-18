#!/bin/bash

###############################################################################
# Flutter Release 빌드 후 Lightsail(EC2) 서버에 APK 업로드 및
# OTA version JSON 갱신 스크립트
###############################################################################

# 사용법: bash ./deploy_apk.sh [common|mammoth]     (기본 common)
#
# 채널은 브랜드가 아니라 **아티팩트**에 종속된다. 전용 아티팩트는 자기 패키지
# 때문에 공통 채널을 물리적으로 쓸 수 없으므로(받아도 패키지 불일치로 설치 실패)
# Tier 1 아티팩트마다 정확히 채널 1세트를 갖는다. 채널명은 슬러그에서 규칙
# 파생한다 — 브랜드마다 손으로 짓지 않는다.
#
#   common  → appfit_order_agent_release.apk         / _release_version.json
#   mammoth → appfit_order_agent_mammoth_release.apk / _mammoth_release_version.json
#
# 서버(live/japanLive/staging)는 앱 로그인 화면에서 런타임 선택되므로 채널과
# 무관하다. 채널을 가르는 것은 패키지뿐이다.

# 0) 브랜드 인자 + 사용자 정의 변수
BRAND="${1:-common}"
case "$BRAND" in
  common|mammoth) ;;
  *)
    echo "[오류] 알 수 없는 브랜드: $BRAND"
    echo "사용법: bash ./deploy_apk.sh [common|mammoth]"
    exit 1
    ;;
esac

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
if [ "$BRAND" = "common" ]; then
  CHANNEL="appfit_order_agent_release"
  EXPECTED_PKG="co.kr.waldlust.order.receive.appfit"
else
  CHANNEL="appfit_order_agent_${BRAND}_release"
  EXPECTED_PKG="co.kr.waldlust.order.receive.appfit.${BRAND}"
fi
APK_NAME="${CHANNEL}.apk"
VERSION_JSON_NAME="${CHANNEL}_version.json"

echo "브랜드: $BRAND / 채널: $CHANNEL / 기대 패키지: $EXPECTED_PKG"

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

echo ".env 주입하여 빌드... (flavor=$BRAND)"
# --flavor 와 --dart-define=APPFIT_BRAND 는 반드시 같은 값이어야 한다. 전자가
# 패키지를, 후자가 인앱 OTA 채널을 결정하므로 어긋나면 매머드 패키지가 공통
# 채널을 폴링하게 된다. 하나의 $BRAND 가 둘을 동시에 구동한다.
# --target-platform: x86_64 AOT 컴파일을 건너뛴다(빌드 시간 단축). 실제 패키징
# 차단의 정본은 android/app/build.gradle.kts 의 release ndk.abiFilters 다 —
# Flutter Gradle 플러그인이 서드파티 AAR 용 abiFilters 를 3종 ABI 로 고정해서
# 이 플래그만으로는 x86_64 네이티브가 안 빠지기 때문.
# armeabi-v7a 는 필수 — D2s_KDS 가 32비트 전용(zygote32)이다. docs/BUILD.md 참조.
flutter build apk --release \
  --flavor "$BRAND" \
  --dart-define=APPFIT_BRAND="$BRAND" \
  --target-platform android-arm,android-arm64 \
  --dart-define-from-file=.env
if [ $? -ne 0 ]; then
  echo "[오류] Flutter 빌드 실패!"
  exit 1
fi

# 빌드된 apk 기본 경로 (플레이버 도입 → app-<flavor>-release.apk)
BUILT_APK="$PROJECT_PATH/build/app/outputs/flutter-apk/app-${BRAND}-release.apk"

# 3) 빌드된 apk 이름 변경
echo "==== 3) Rename app-${BRAND}-release.apk -> $APK_NAME ===="
if [ ! -f "$BUILT_APK" ]; then
  echo "[오류] 빌드 산출물 없음: $BUILT_APK"
  exit 1
fi

mv "$BUILT_APK" "$PROJECT_PATH/$APK_NAME"
if [ ! -f "$PROJECT_PATH/$APK_NAME" ]; then
  echo "[오류] 이름 변경 실패! $PROJECT_PATH/$APK_NAME 확인 요망."
  exit 1
fi

###############################################################################
# 3-1) 업로드 직전 패키지 검증 — 채널·아티팩트 교차 업로드 방지
#
# 잘못된 패키지를 채널에 올리면 그 채널을 폴링하는 전 함대가 "다운로드는 되는데
# 설치는 실패"에 빠지고, 되돌릴 방법이 없다(기기가 이미 새 버전 번호를 봤다).
# 레거시 무접미 채널이 동결된 원인이 정확히 이 사고다. 그래서 여기서 막는다.
###############################################################################
echo "==== 3-1) Verify APK package matches channel ===="
AAPT=""
if command -v aapt >/dev/null 2>&1; then
  AAPT="aapt"
else
  SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/AppData/Local/Android/Sdk}}"
  AAPT=$(ls -1 "$SDK_DIR"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
  [ -z "$AAPT" ] && AAPT=$(ls -1 "$SDK_DIR"/build-tools/*/aapt.exe 2>/dev/null | sort -V | tail -1)
fi

if [ -n "$AAPT" ]; then
  BADGING=$("$AAPT" dump badging "$PROJECT_PATH/$APK_NAME" 2>/dev/null)
  ACTUAL_PKG=$(echo "$BADGING" | sed -n "s/.*package: name='\([^']*\)'.*/\1/p")
  ACTUAL_VC=$(echo "$BADGING" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
  ACTUAL_LABEL=$(echo "$BADGING" | sed -n "s/^application-label:'\([^']*\)'.*/\1/p")
  echo "   package     : $ACTUAL_PKG"
  echo "   versionCode : $ACTUAL_VC"
  echo "   label       : $ACTUAL_LABEL"
  if [ "$ACTUAL_PKG" != "$EXPECTED_PKG" ]; then
    echo "###############################################################################"
    echo "[중단] 패키지가 채널과 맞지 않습니다."
    echo "   채널        : $CHANNEL"
    echo "   기대 패키지 : $EXPECTED_PKG"
    echo "   실제 패키지 : $ACTUAL_PKG"
    echo "이대로 올리면 그 채널을 폴링하는 기기가 전부 설치 실패에 빠집니다."
    echo "###############################################################################"
    exit 1
  fi
  echo "✅ 패키지 검증 통과"
else
  echo "###############################################################################"
  echo "[중단] aapt 를 찾을 수 없어 패키지를 검증할 수 없습니다."
  echo "ANDROID_HOME 을 설정하거나 build-tools 를 설치하십시오."
  echo "검증 없는 업로드는 되돌릴 수 없는 사고로 이어질 수 있어 진행하지 않습니다."
  echo "###############################################################################"
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
bash "$PROJECT_PATH/archive_apk.sh" "$PROJECT_PATH/$APK_NAME" "$BRAND"

echo "###############################################################################"
echo "[완료] ($BRAND) $APK_NAME 업로드 완료!"
echo "서버 경로: $REMOTE_HOST:$REMOTE_DIR/$APK_NAME"
echo "OTA 업데이트 URL: http://waldpay.kokonutstamp2.com/$APK_NAME"
echo "버전 JSON URL: http://waldpay.kokonutstamp2.com/$VERSION_JSON_NAME (version=$BUILD_NUMBER)"
echo "###############################################################################"
