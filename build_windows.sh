#!/bin/bash

# 윈도우 릴리스 빌드 스크립트
# 사용법: bash build_windows.sh

set -e

echo "🚀 Windows Release 빌드 시작..."
echo ""

# 의존성 확인
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter를 찾을 수 없습니다. Flutter SDK를 설치하세요."
    exit 1
fi

# 빌드 실행
echo "📦 Windows Release 빌드 중..."
flutter build windows --release

BUILD_OUTPUT="build/windows/x64/runner/Release"

if [ -d "$BUILD_OUTPUT" ]; then
    echo ""
    echo "✅ 빌드 완료!"
    echo "📂 출력 폴더: $BUILD_OUTPUT"
    echo ""

    # 빌드 폴더 자동 열기 (Git Bash, WSL 환경에 따라 다름)
    if command -v explorer.exe &> /dev/null; then
        # Windows 환경 (Git Bash, WSL)
        explorer.exe "$(pwd)/$BUILD_OUTPUT" 2>/dev/null || echo "⚠️  폴더를 수동으로 열어주세요: $BUILD_OUTPUT"
    else
        # 다른 환경
        echo "⚠️  폴더를 수동으로 열어주세요: $BUILD_OUTPUT"
    fi
else
    echo ""
    echo "❌ 빌드 실패: 출력 폴더를 찾을 수 없습니다."
    exit 1
fi

echo ""
echo "💡 다음 파일들을 배포하세요:"
echo "   - appfit_order_agent.exe (메인 실행파일)"
echo "   - vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll (필수 DLL)"
echo "   - data/, flutter_windows.dll 등 (의존성 파일)"
