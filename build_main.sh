#!/bin/bash

###############################################################################
# Android 릴리즈 APK 빌드 (배포 없이 로컬 빌드 + 아카이브)
#
# 사용법: bash ./build_main.sh [common|mammoth|all]     (기본 common)
#
# 2-티어 아티팩트 모델:
#   common  — Tier 0 공통. 모든 브랜드의 기본. 패키지 ….appfit
#   mammoth — Tier 1 매머드 전용. 패키지 ….appfit.mammoth, 전용 런처 이름·아이콘
#
# 두 아티팩트는 **같은 코드·같은 버전·같은 서명키**다. 다른 것은 OS 셸
# 아이덴티티(applicationId, 런처 label/icon)와 OTA 채널뿐이며, 브랜드 로직은
# 전부 런타임(BrandRegistry)이다. 서버(live/japanLive/staging)는 로그인 화면에서
# 런타임 선택되므로 빌드와 무관하다.
###############################################################################

set -u

# 0) 브랜드 인자 파싱
BRAND="${1:-common}"
case "$BRAND" in
  common|mammoth|all) ;;
  *)
    echo "[오류] 알 수 없는 브랜드: $BRAND"
    echo "사용법: bash ./build_main.sh [common|mammoth|all]"
    exit 1
    ;;
esac

# 프로젝트 정보 추출
PROJECT_NAME=$(grep "^name:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
VERSION=$(grep "^version:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
BUILD_DATE=$(date +%Y%m%d)

# 브랜드 → applicationId (android/app/build.gradle.kts 의 productFlavors 와 일치)
app_id_for() {
  case "$1" in
    common)  echo "co.kr.waldlust.order.receive.appfit" ;;
    mammoth) echo "co.kr.waldlust.order.receive.appfit.mammoth" ;;
  esac
}

###############################################################################
# 한 브랜드 빌드
###############################################################################
build_one() {
  local brand="$1"
  local app_id
  app_id="$(app_id_for "$brand")"

  echo ""
  echo "=== Appfit 주문 접수 앱 빌드 시작 ($brand) ==="
  echo "패키지명: $app_id"
  echo "앱 이름: $PROJECT_NAME"
  echo "버전: $VERSION"
  echo "빌드 날짜: $BUILD_DATE"
  echo ""

  # Android APK 빌드
  #
  # --flavor 와 --dart-define=APPFIT_BRAND 는 **반드시 같은 값**이어야 한다.
  # --flavor 가 패키지를, APPFIT_BRAND 가 인앱 OTA 채널을 결정하므로, 어긋나면
  # 매머드 패키지가 공통 채널을 폴링하고 받은 APK 는 패키지 불일치로 설치가
  # 실패한다. 그래서 하나의 $brand 변수가 둘을 동시에 구동한다.
  #
  # --target-platform: x86_64 AOT 컴파일을 건너뛴다(빌드 시간 단축). 실제 패키징
  # 차단의 정본은 android/app/build.gradle.kts 의 release ndk.abiFilters 다 —
  # Flutter Gradle 플러그인이 서드파티 AAR 용 abiFilters 를 3종 ABI 로 고정해서
  # 이 플래그만으로는 x86_64 네이티브가 안 빠지기 때문.
  # armeabi-v7a 는 필수 — D2s_KDS 가 32비트 전용(zygote32)이다. docs/BUILD.md 참조.
  echo "Android APK 빌드 중 (flavor=$brand)..."
  flutter build apk --release \
    --flavor "$brand" \
    --dart-define=APPFIT_BRAND="$brand" \
    --target-platform android-arm,android-arm64 \
    --dart-define-from-file=.env
  if [ $? -ne 0 ]; then
    echo "[오류] Flutter 빌드 실패 ($brand)!"
    return 1
  fi

  # 플레이버 도입 후 산출물명은 app-<flavor>-release.apk 다.
  local original_apk="build/app/outputs/flutter-apk/app-${brand}-release.apk"
  local new_apk_name="${PROJECT_NAME}_${brand}_v${VERSION}_${BUILD_DATE}.apk"
  local new_apk_path="build/app/outputs/flutter-apk/${new_apk_name}"

  if [ ! -f "$original_apk" ]; then
    echo "[오류] 빌드 결과물을 찾을 수 없습니다: $original_apk"
    return 1
  fi

  echo ""
  echo "=== APK 파일명 변경 중... ==="
  mv "$original_apk" "$new_apk_path"
  echo "변경 완료: $new_apk_name"

  # 패키지 확인 (aapt 가 있으면). 플레이버/브랜드 어긋남을 여기서 잡는다.
  local badging
  badging="$(_aapt_badging "$new_apk_path")"
  if [ -n "$badging" ]; then
    local actual_pkg actual_label version_code
    actual_pkg=$(echo "$badging" | sed -n "s/.*package: name='\([^']*\)'.*/\1/p")
    version_code=$(echo "$badging" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
    actual_label=$(echo "$badging" | sed -n "s/^application-label:'\([^']*\)'.*/\1/p")
    echo "   package     : $actual_pkg"
    echo "   versionCode : $version_code"
    echo "   label       : $actual_label"
    if [ "$actual_pkg" != "$app_id" ]; then
      echo "[오류] 패키지 불일치! 기대=$app_id 실제=$actual_pkg"
      return 1
    fi
  else
    echo "   (aapt 없음 — 패키지 확인 건너뜀)"
  fi

  echo ""
  echo "=== APK 빌드 완료 ($brand) ==="
  echo "APK 파일 위치: $new_apk_path"
  echo "설치 명령어: adb install $new_apk_path"

  # 로컬 아카이브 보관 + 노트 기록 + 폴더 열기
  bash ./archive_apk.sh "$new_apk_path" "$brand"
}

# aapt 로 badging 을 뽑는다. 없으면 빈 문자열(호출 측이 건너뛴다).
_aapt_badging() {
  local apk="$1"
  local aapt=""
  if command -v aapt >/dev/null 2>&1; then
    aapt="aapt"
  elif command -v aapt2 >/dev/null 2>&1; then
    aapt="aapt2"
  else
    local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/AppData/Local/Android/Sdk}}"
    aapt=$(ls -1 "$sdk"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
    [ -z "$aapt" ] && aapt=$(ls -1 "$sdk"/build-tools/*/aapt.exe 2>/dev/null | sort -V | tail -1)
  fi
  [ -z "$aapt" ] && return 0
  "$aapt" dump badging "$apk" 2>/dev/null
}

###############################################################################
# 실행
###############################################################################
echo "1. Flutter clean 실행 중..."
flutter clean

echo "2. Flutter pub get 실행 중..."
flutter pub get

if [ "$BRAND" = "all" ]; then
  # 같은 커밋·같은 버전으로 연속 빌드한다. versionCode 는 pubspec.yaml 하나가
  # 정본이므로 두 APK 가 반드시 같아야 한다(위 badging 출력으로 육안 확인).
  build_one common || exit 1
  build_one mammoth || exit 1
else
  build_one "$BRAND" || exit 1
fi

echo ""
echo "Build completed!"
