---
name: project_dual_variant_build
description: "update/standalone 두 패키지 변형 빌드 골격 — 왜, .appfit suffix, 영구 GUID, 설정 비승계, Windows 격리 키"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0b55c1f5-6bed-442c-89e0-aea2d78cf4a3
---

단일 코드베이스에서 두 변형으로 빌드한다. **update**(applicationId `co.kr.waldlust.order.receive`, 구앱 덮어쓰기·설정 자동 승계·기존 OTA 호환)와 **standalone**(`co.kr.waldlust.order.receive.appfit`, 구앱과 병존 설치). 목적: 900개 매장(전부 SUNMI D3MINI/T2MINI_S, Windows는 예외 ≤5)에 서비스 개시 전 미리 설치해 업데이트 지연 리스크 제거. **아직 패키지 분리 확정 아님 — 선제적으로 골격만 준비함.**

**Why:** 과거 kokonut 업데이트 경험상 전 매장 OTA 완료까지 수일 소요. 개시일에 일부 매장이 구앱이면 리스크 큼.

**How to apply:**
- standalone은 설정 자동 승계 불가 = **신규 설치 취급**(샌드박스 분리). 재로그인+전체 재설정 전제(매장 사전 교육으로 흡수). 마이그레이션 로직은 의도적 미구현 — 추가하지 말 것(범위 결정).
- 병존 설치는 AndroidManifest `${applicationId}.fileProvider` 동적 authority에 의존(하드코딩이면 INSTALL_FAILED_CONFLICTING_PROVIDER). firebaseinitprovider 등도 자동 .appfit 네임스페이스.
- Windows 변형 격리의 열쇠는 `windows/runner/Runner.rc`의 ProductName 분기(path_provider_windows가 `%APPDATA%\CompanyName\ProductName` 사용 → SharedPreferences 자동 분리). 뮤텍스명(main.cpp)·BINARY_NAME(windows/CMakeLists.txt)도 `APPFIT_VARIANT_STANDALONE` 매크로/`APPFIT_WINDOWS_VARIANT` 환경변수로 분기. CMake 캐시 때문에 변형 전환 시 build/windows clean 필요(빌드 스크립트가 sentinel로 자동 처리).
- Firebase는 `lib/firebase_options.dart` 하드코딩(gradle에 google-services 플러그인 없음, google-services.json은 死 파일) → standalone 콘솔 작업 불필요.
- **standalone Inno AppId GUID = `E448C213-990C-AEED-03A8-6A695F9EED14` (영구, 재생성 금지).** update는 기존 `8E19A1C4-AFDA-4061-B0FF-186FB71B1745`.
- 빌드: `./build_main.sh [update|standalone]` / `./deploy_apk.sh [update|standalone]`, Windows `.\build_windows.ps1|deploy_windows.ps1|build_installer.ps1 -Variant [update|standalone]`. flavor 도입 후 flavor 미지정 빌드는 실패함.

관련: [[project_appfit_core_dual_repo]], [[reference_windows_toolchain_quirks]], [[project_store_printer_topology]].
