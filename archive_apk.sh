#!/bin/bash

###############################################################################
# APK 산출물을 로컬 공용 보관소에 아카이브하고 빌드 노트를 기록한 뒤
# 해당 버전 폴더를 Finder 로 연다.
#
# 사용법: bash ./archive_apk.sh <built_apk_path> <flavor>
#   - <built_apk_path> : 보관할 APK 파일 경로
#   - <flavor>         : update(기본) | standalone
#
# 보관 구조: <ARCHIVE_BASE>/<프로젝트명>/apk/<버전>/<APK> + release_notes_<flavor>.txt
#   예) /Users/.../!Project Files/appfit_order_agent/apk/3.3.6+152/
#
# 주의: deploy/build 가 이미 끝난 뒤 호출되므로, 아카이브 실패가 전체 흐름을
#       중단시키지 않도록 항상 경고만 출력하고 exit 0 으로 끝낸다.
###############################################################################

SRC_APK="$1"
FLAVOR="${2:-update}"

# 공용 보관소 베이스. archive_windows.ps1 과 동일하게 홈 디렉터리에서 동적으로
# 구해 머신/OS 에 무관하게 동작한다 (macOS: /Users/<user>, Windows Git Bash:
# /c/Users/<user>). ARCHIVE_BASE 환경변수로 재정의 가능.
# 경로의 '!' 는 비대화형 bash 에서 history expansion 이 꺼져 있고 큰따옴표
# 변수로만 전개하므로 안전하다.
HOME_DIR="${HOME:-${USERPROFILE:-}}"
ARCHIVE_BASE="${ARCHIVE_BASE:-${HOME_DIR}/Documents/!Project Files}"

# pubspec.yaml 에서 프로젝트명/버전 추출 (build_main.sh 와 동일한 추출식)
PROJECT_NAME=$(grep "^name:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
VERSION=$(grep "^version:" pubspec.yaml | cut -d' ' -f2 | tr -d '"' | tr -d "'")
BUILD_NUMBER=$(echo "$VERSION" | sed 's/.*+//')

# flavor -> 패키지명
if [ "$FLAVOR" = "standalone" ]; then
  APP_ID="co.kr.waldlust.order.receive.appfit"
else
  APP_ID="co.kr.waldlust.order.receive"
fi

ARCHIVE_DIR="$ARCHIVE_BASE/$PROJECT_NAME/apk/$VERSION"

echo "==== Archive APK to local Project Files ===="

# 소스 APK 확인
if [ ! -f "$SRC_APK" ]; then
  echo "[경고] 아카이브할 APK 가 없습니다: $SRC_APK (아카이브 건너뜀)"
  exit 0
fi

# 보관 폴더 생성 (프로젝트/apk/버전 3단계 한 번에)
mkdir -p "$ARCHIVE_DIR" || {
  echo "[경고] 아카이브 폴더 생성 실패: $ARCHIVE_DIR (아카이브 건너뜀)"
  exit 0
}

# APK 복사 (동일 버전 재빌드 시 덮어쓰기)
cp "$SRC_APK" "$ARCHIVE_DIR/" || {
  echo "[경고] APK 복사 실패: $SRC_APK -> $ARCHIVE_DIR (아카이브 건너뜀)"
  exit 0
}

# 빌드 노트 기록 (flavor 별 분리, 덮어쓰기)
NOTES_FILE="$ARCHIVE_DIR/release_notes_${FLAVOR}.txt"
{
  echo "=== $PROJECT_NAME 빌드 노트 ==="
  echo "버전: $VERSION"
  echo "빌드번호: $BUILD_NUMBER"
  echo "변형(flavor): $FLAVOR"
  echo "패키지명: $APP_ID"
  echo "빌드 일시: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "APK 파일: $(basename "$SRC_APK")"
  echo ""
  echo "--- 최근 git 커밋 (5) ---"
  git log --oneline -5 2>/dev/null || echo "(git 정보 없음)"
} > "$NOTES_FILE"

echo "✅ 아카이브 완료: $ARCHIVE_DIR"
echo "   - APK: $(basename "$SRC_APK")"
echo "   - 노트: $(basename "$NOTES_FILE")"

# 보관한 버전 폴더 열기 (OS 별 분기: Windows 탐색기 / macOS Finder / Linux)
if command -v explorer.exe >/dev/null 2>&1; then
  # Git Bash 경로(/c/...) 를 Windows 경로로 변환해 탐색기로 연다
  if command -v cygpath >/dev/null 2>&1; then
    explorer.exe "$(cygpath -w "$ARCHIVE_DIR")" 2>/dev/null || true
  else
    explorer.exe "$ARCHIVE_DIR" 2>/dev/null || true
  fi
elif command -v open >/dev/null 2>&1; then
  open "$ARCHIVE_DIR" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$ARCHIVE_DIR" 2>/dev/null || true
fi
