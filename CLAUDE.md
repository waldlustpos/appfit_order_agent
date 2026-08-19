# CLAUDE.md

## 프로젝트 개요

**AppFit 주문 에이전트** — 카페·음식 업종에서 키오스크/모바일 주문을 접수·관리하는 Flutter 앱. **Android 가로 전용 + Windows 데스크톱**, 메인 모드(주문 접수)와 KDS 모드(주방 디스플레이) 토글. 주력 디바이스: Sunmi D3 MINI, D2s_KDS, Windows POS.

- 패키지: `co.kr.waldlust.order.receive.appfit` (Tier 0 공통) / `co.kr.waldlust.order.receive.appfit.mammoth` (Tier 1 매머드 전용). **국가는 빌드를 가르지 않는다** — 서버 live/japanLive/staging 은 로그인 화면에서 런타임 선택되고 매장 ID 프리픽스로 자동 전환된다. 빌드를 가르는 축은 브랜드 아티팩트 티어 하나뿐이며, 사정거리는 applicationId·런처 label/icon·OTA 채널까지다(`lib/config/build_brand.dart`).
- **Android 는 product flavor 를 쓴다 — `--flavor` 없는 빌드는 실패한다.** `--flavor <slug>` 와 `--dart-define=APPFIT_BRAND=<slug>` 를 **반드시 같은 값으로 함께** 넘긴다(어긋나면 매머드 패키지가 공통 OTA 채널을 폴링해 설치 실패에 빠진다). 스크립트는 `./build_main.sh [common|mammoth|all]`, `./deploy_apk.sh [common|mammoth]`.
- Dart SDK: ^3.5.0, Flutter: >=3.19.0
- Android: minSdk 24, targetSdk 35
- Windows: x64 release, Inno Setup 6 인스톨러, 단일 인스턴스 뮤텍스
- 버전 정본: **Android·Windows 모두 `pubspec.yaml`의 `version`** (`x.y.z+n`). 과거 Windows 전용이던 `version_windows.txt`는 폐지됨

## 핵심 명령어

- 의존성/코드 생성: `flutter pub get` → `flutter pub run build_runner build --delete-conflicting-outputs` (freezed/riverpod) → `flutter pub run slang` (i18n `strings.g.dart`)
  - slang 은 standalone(`slang_build_runner` 미사용)이라 **build_runner 로는 `strings.g.dart` 가 갱신되지 않음**. i18n JSON 수정 후엔 `flutter pub run slang` 필수. Flutter 라 `dart run` 대신 `flutter pub run` 사용.
- 분석: `flutter analyze`
- 릴리즈 빌드/배포: `./build_main.sh`, `./deploy_apk.sh`
- 자세한 명령어·환경설정·다국어 워크플로: [docs/BUILD.md](docs/BUILD.md)

## 절대 규칙
- **설명은 한국어를 기본으로 함**
- **생성 파일 직접 수정 금지**: `.g.dart` / `.freezed.dart`는 항상 build_runner 재실행으로 갱신.
- **모델은 수동 작성**: `lib/models/`는 freezed/json_serializable을 **사용하지 않음**. `fromJson`/`toJson`/`copyWith` 직접 구현. Claude가 freezed로 새 모델을 만들지 말 것.
- **API 요청 우회 금지**: 모든 REST 호출은 `appfit_core`의 Dio 인터셉터 경유 (자동 인증 헤더 + AES-GCM 암호화). 직접 `http`/`Dio`로 요청하지 말 것.
- **프로젝트 내부 import 는 `package:` 형태만**: 상대 import(`../`) 금지. 모든 `lib/` 내부 참조는 `package:appfit_order_agent/...`. `always_use_package_imports` 린트로 강제(파일 이동에 불변, stale import 를 컴파일 에러로 검출). 상세: [docs/FLUTTER_GUIDELINES.md](docs/FLUTTER_GUIDELINES.md).
- **인증/세션 정리는 단일 진입점**: `Auth.logout()`(`lib/providers/auth_provider.dart`)만 사용. `disconnect()` 호출 후에는 dependency가 outdated되므로 **모든 `ref.read()`는 disconnect 호출 전에 미리 캐시**해야 함. UI 계층은 `Auth.logout()` 호출 + 영업 상태 변경 + `OrderProvider` cleanup + 네비게이션만 담당.
- **버전 정본은 `pubspec.yaml` 하나**: `build_windows.ps1` / `deploy_windows.ps1` / `build_installer.ps1` / `archive_windows.ps1` / `build_windows.sh` 모두 `pubspec.yaml`의 `version`(`x.y.z+n`)에서 build-name/build-number를 읽어 `--build-name` / `--build-number`(+ `--dart-define=WINDOWS_APP_VERSION`/`WINDOWS_APP_BUILD`)로 주입. Android/Windows 버전이 함께 올라가므로 **한쪽만 배포해도 버전 번호는 공유**된다. PowerShell 스크립트는 한국어 콘솔에서 깨지지 않도록 **UTF-8 BOM**으로 저장.
- **빌드/네이티브 소스는 ASCII만**: `.cpp`/`.h`/`.cmake`/`CMakeLists.txt`/`.gradle`/`.ps1`/`.bat` 의 코드·주석·문자열에 em-dash(`—`), en-dash(`–`), 전각 따옴표(`" "` `' '`), 물결(`～`), `…` 등 비-ASCII 문자 금지. C/C++ 소스에 한국어 주석 금지 (MSVC 가 BOM 없는 UTF-8 을 CP949 로 해석해 C4819 경고·문자열 깨짐 사고). 한국어 설명은 `.md` 또는 Dart(`lib/**/*.dart`) 에만. autoreplyprint 통합 등 향후 native 모듈 작업 시 동일 적용.

## 상세 문서

- **점주·브랜드 담당자용 안내서**(kokonut→AppFit 변화점 + 화면별 사용법 + 운영 확인사항. 단일 HTML·브라우저에서 A4 PDF 저장. 개발 용어 금지, 배포용 정본): [docs/guide/appfit-agent-guide.html](docs/guide/appfit-agent-guide.html) — 설정 항목·상태 전이 버튼·프린터 지원 모델·업데이트 정책이 바뀌면 함께 갱신 ([docs/FEATURES.md](docs/FEATURES.md) 는 이 문서를 가리키는 포인터만 유지)
- **점주용 설치 가이드**(Sunmi 단말 App Store 설치 → 권한 허용 → 첫 로그인. 공통 1~3단계 + **기기별 트랙**(T2mini 4~6 / D3mini 4~8) + 공통 로그인. 실기기 캡처에 CSS 오버레이(`.hl`, 이미지 기준 % 좌표)로 강조, 이미지 base64 임베드 단일 HTML): [docs/guide/Sunmi-appfit-agent-install-guide.html](docs/guide/Sunmi-appfit-agent-install-guide.html) — 설치 절차·권한 항목이 바뀌면 캡처와 함께 갱신
  - **매머드 전용 판**(Tier 1 아티팩트 `매머드오더 에이전트` 캡처·매장 ID `MMTH` 기준. D3mini 트랙이 4~10단계로 확장 — 알림/모든 파일/음악/사진 권한을 하나씩 따로 요청): [docs/guide/Sunmi-mammoth-agent-install-guide.html](docs/guide/Sunmi-mammoth-agent-install-guide.html) — 공통판과 **별도 문서**이므로 절차가 바뀌면 두 문서를 함께 갱신
- 아키텍처(데이터 흐름·Riverpod·서비스·UI·네이티브·브랜드 테마·주요 패턴): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 사운드그래프(MHST) 연동 흐름 도식(As-Is kokonut 왕복 ↔ To-Be 구서버 중계안·Firestore 제거 권고): [docs/SOUNDGRAPH.md](docs/SOUNDGRAPH.md)
- 빌드/배포/환경설정/다국어(Slang): [docs/BUILD.md](docs/BUILD.md)
- 릴리즈/배포 정책(단일 코드·단일 아티팩트·이중 채널: OTA `_release` + Sunmi App Store gray, 롤아웃 순서·핫픽스·브랜드 온보딩 규칙): [docs/RELEASE.md](docs/RELEASE.md)
- Flutter/Dart 코드 스타일·Riverpod·라우팅·로깅·테마·테스트·접근성 규약: [docs/FLUTTER_GUIDELINES.md](docs/FLUTTER_GUIDELINES.md)
- 테스트 작성·실행 방법(characterization 전략·PreferenceService seam·fake 패턴): [docs/TESTING.md](docs/TESTING.md)
- 브랜드별 라벨/영수증 로고 자원 분기·BMP 사양·새 브랜드 추가 절차: [docs/BRAND_ASSETS.md](docs/BRAND_ASSETS.md)
- 리팩토링 로드맵(Phase 0~3·하지 말 것 목록·작업 규율): [docs/REFACTORING.md](docs/REFACTORING.md)
- 기기 관제(Fleet: 앱 실행상태 heartbeat·기기정보 등록·원격 로그 요청. 백엔드는 별도 레포 `appfit-fleet`, 공통 리포터는 `appfit_core`. **대상 매장 화이트리스트로 게이팅** — 목록 정본은 [fleet_targets/](fleet_targets/), 서버 업로드는 수동 scp): [docs/DEVICE_MONITORING.md](docs/DEVICE_MONITORING.md)
- Sentry 에러 알림 라우팅(매장/브랜드별 store_id 태그 → Slack 채널 분기, `routes.json` 정본 + `sentry_alerts/` 스크립트, add-brand 연동): [docs/SENTRY_ALERTS.md](docs/SENTRY_ALERTS.md)
- As-Is 아키텍처 요약(Outline 게시용·표 중심): [docs/AS-IS.md](docs/AS-IS.md)
- C4 모델 개념·작성 규약(4개 repo 공통 정본): [docs/C4_GUIDE.md](docs/C4_GUIDE.md)
- C4 시각 모델(L1~L4+특화 뷰, 진입점 `c4core-context.html` — 아키텍처 변경 시 함께 갱신, 검증은 `agentc4model/verify_c4.py`): [agentc4model/](agentc4model/)
- Claude 메모리 공유(메모리 정본은 `.claude/memory/`, 머신별 홈 경로에서 심볼릭 링크 — 새 머신 최초 1회 셋업): [.claude/MEMORY_SETUP.md](.claude/MEMORY_SETUP.md)
