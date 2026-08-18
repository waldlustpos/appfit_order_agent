# 릴리즈 / 배포 정책

코드 관리·배포 채널·롤아웃 절차의 정본입니다. 빌드 명령어·스크립트 상세는 [BUILD.md](BUILD.md), 채널/버전 도식은 [BUILD_VARIANTS.md](BUILD_VARIANTS.md) 참조. 코드 관리(브랜치·태그·핫픽스) 규율은 저장소 공통이며, 채널·롤아웃 절은 Android 기준입니다 — Windows 는 Sunmi App Store 와 무관한 단일 OTA 채널이므로 [BUILD.md](BUILD.md) Windows 절 참조.

## 대원칙: 티어별 아티팩트, 채널은 아티팩트에 종속

- **코드는 단일 코드베이스·단일 main.** 브랜드 전용 포크/장수 브랜치를 만들지 않는다. 브랜드 **동작**의 차이는 `lib/utils/brand_registry.dart` 의 `BrandFeature` 로 런타임 분기한다 — 이건 브랜드가 몇 개든 불변이다.
- **빌드는 2-티어 아티팩트 모델을 따른다.**
  - **Tier 0(기본)** — 공통 아티팩트. 대부분의 브랜드가 여기 속하며, 한국/일본을 포함해 빌드를 나누지 않는다(2026-07-09 변형 폐기 참조). 릴리즈당 APK 1개를 두 채널에 올린다.
  - **Tier 1(예외, opt-in)** — 전용 아티팩트. 같은 코드·같은 버전이고 **OS 셸 아이덴티티만**(applicationId, 런처 label/icon, Windows exe명/mutex/설치 GUID) 다르다. 승격 조건 3개(전부 충족해야 함): ① 자체 App Store 리스팅/유통 경로 요구 ② 함대가 해당 브랜드 기기 전용(혼재 없음) ③ 런처 이름·아이콘이 계약·운영상 요구사항. `/add-brand` 마지막 단계에서 이 3문항을 강제로 묻는다(기본 Tier 0). 현재 Tier 1: **맘모스**(패키지 `co.kr.waldlust.order.receive.appfit.mammoth`, Windows exe `appfit_order_agent_mammoth.exe`).
- **채널 불변식 — 채널은 브랜드가 아니라 아티팩트에 종속된다.** Tier 1 아티팩트는 자기 패키지/exe명 때문에 공통 채널을 물리적으로 쓸 수 없다(받아도 패키지 불일치·자연 업데이트 불가로 설치 실패). 그래서 Tier 1 아티팩트마다 **정확히 채널 1세트**를 부여한다. 뒤집으면 이게 증식 방지선이다 — **아티팩트 없이 채널만 늘리지 않는다.** 채널 수는 항상 아티팩트 수와 같다. 채널명은 슬러그에서 규칙 파생한다(`appfit_order_agent_<brand>_release.*`, `appfit_order_agent_<brand>_windows.*`) — 브랜드마다 손으로 짓지 않는다.
- **분리는 유통 채널에서만** 한다:

| 채널 | 대상 함대 | 롤아웃 제어 |
| --- | --- | --- |
| OTA `_release` (`deploy_apk.sh common` → Lightsail) | **`sunmiAppStoreUpdate` 브랜드+Sunmi 를 제외한 모든 공통(Tier 0) 기기** — 비 Sunmi 안드로이드 전체 + 그 기능이 **없는** 브랜드의 Sunmi 기기(TPCP/MATA/기타) + 수동 체크 | 없음 — 업로드 후 각 기기의 **다음 앱 시작(로그인 화면 진입) 시** 자동체크 ON 기기 전량에 반영, 비율 제어 불가 |
| Sunmi App Store (수동 업로드, gray 기기 타깃, `/store-upload`) | `sunmiAppStoreUpdate` 브랜드의 Sunmi 기기 (현재 **맘모스**가 유일 대상) | gray 타깃으로 매장/기기 단위 단계 배포 가능 |
| OTA `_mammoth_release` (`deploy_apk.sh mammoth` → Lightsail) | 맘모스(Tier 1) 아티팩트의 비-Sunmi 단말 + 수동 체크 안전망. **실제 운영 정책은 Sunmi 스토어 경로** — 이 채널은 구조적 대비 + 안전망이다 | 위와 동일(비율 제어 불가). 빈 채널은 안전망이 아니므로(404 는 조용히 삼켜진다) 릴리즈마다 함께 채운다 |

## 기기별 업데이트 정책 (코드에 이미 구현됨)

- **정책(2026-07-22 반전)**: `sunmiAppStoreUpdate` 브랜드(현재 **맘모스** — `MMTH`/`MHST` 프리픽스 둘 다) + Sunmi = Sunmi App Store 채널(자동 OTA 체크 OFF), **그 외 모든 조합 = OTA 채널(자동 체크 ON)**. 이전엔 "Sunmi 전부 OFF + TPCP 만 ON 예외" 였으나, "전부 ON + 해당 브랜드만 OFF 예외" 로 뒤집혔다.
- 로그인 전 기본값: 자동 OTA 체크는 **Sunmi 기기 OFF, 그 외 ON** (`lib/services/preference_service.dart` `_initializeUpdateDefaults`). 이는 브랜드 미상 상태의 보수적 기본값(맘모스 첫 실행 스푸리어스 OTA 방지)일 뿐이며, 최종 판정은 아래 로그인 재조정이 한다.
- **로그인 재조정**(`login_screen.dart`, `_login` 성공 분기): 설치 후 최초 로그인 1회, `sunmiAppStoreUpdate` 브랜드 + Sunmi 면 자동 체크 OFF, 그 외엔 ON 으로 세팅. 이후 사용자 수동 토글을 존중한다(`getUpdatePolicyReconciled` / `KEY_UPDATE_POLICY_MHST_SUNMI_V1` 마커 — **문자열은 역사적 이름 그대로 유지**한다. 이미 배포된 멱등 마커라 이름을 바꾸면 전 기기가 정책 재조정을 한 번 더 수행한다). 자동·수동 로그인 공용 경로라 auto-login 기기도 다음 로그인 때 재조정된다.
  - **기존 fleet 마이그레이션**: 마커 문자열이 새 값이라, 기존 설치 기기 전부 다음 로그인 때 1회 재조정된다 — 비맘모스 Sunmi(기존 OFF)는 **ON(OTA)로 전환**, 맘모스+Sunmi 는 OFF 유지.
- **신규 브랜드 온보딩 결정 규칙**: "이 브랜드의 Sunmi 기기가 Sunmi App Store 관리 함대에 들어가는가?" — YES 면 `BrandFeature.sunmiAppStoreUpdate` 부여(→ OFF/앱스토어), NO 면 기능 없이 기본(→ ON/OTA). 이 결정은 Tier 0/Tier 1 과 독립이다 — 패키지를 나누지 않은 브랜드도 이 기능은 가질 수 있다.

## 릴리즈 절차

아래는 Tier 0(공통) 기준. Tier 1(맘모스)은 같은 절차를 브랜드 인자만 붙여
반복한다(`./build_main.sh mammoth`, `./deploy_apk.sh mammoth`, `/store-upload
mammoth`) — 버전 정본은 하나이므로 두 아티팩트를 **같은 커밋·같은 버전**으로
함께 진행하는 것을 권장한다(`./build_main.sh all` 로 연속 빌드).

1. `pubspec.yaml` 버전 상승(versionCode `+n` 단조 증가) → 커밋 → **`git tag vX.Y.Z`** (어느 커밋이 몇 매장에 깔려 있는지 추적하는 유일한 수단).
2. 릴리즈 빌드: `flutter build apk --release --flavor common --dart-define=APPFIT_BRAND=common --dart-define-from-file=.env` (또는 `./build_main.sh`).
3. 그 APK 를 **Sunmi App Store 에 업로드**(`/store-upload`), gray 로 소수 매장 canary 타깃.
4. canary 검증 후 gray 범위 확대.
5. 검증 완료 후 마지막에 `./deploy_apk.sh` 로 **OTA `_release` 갱신**. OTA 는 비율 제어가 없으므로 항상 맨 뒤에 놓는다.

### 채널 간 호환 불변식

- 두 채널 사이에서 기기가 어느 쪽 APK 로도 설치·업데이트될 수 있으려면 **같은 서명키 + 같은 versionCode** 여야 한다. Android 업데이트 요건은 동일 패키지 + 동일 서명 + versionCode ≥ 이므로 바이트 동일성까지는 필요 없다 — 5단계의 `deploy_apk.sh` 재빌드는 같은 커밋·같은 버전이면 문제없다.
- **두 업로드 사이에 커밋/버전을 바꾸지 말 것.** 수정이 필요해지면 버전을 올리고 1단계부터 다시 시작한다.
- 채널별 롤아웃 속도가 다르므로 함대에 버전 N/N-1 이 상시 공존한다. 서버 API·프로토콜 변경은 이 스큐를 전제로 한다.

## 핫픽스 절차

- Sunmi store 심사/gray 진행 중 긴급 수정이 필요할 때만: 배포된 `vX.Y.Z` 태그에서 `release/x.y` 브랜치 절단 → main 의 수정 커밋 cherry-pick → 버전 상승 → 새 태그 → 위 릴리즈 절차. 완료 후 브랜치는 정리한다 — **장수 브랜드 브랜치 금지.**

## 하지 말 것

- **아티팩트 없이 채널만 늘리지 않는다.** 새 브랜드 전용 채널이 필요해 보이면 먼저 Tier 1 승격 조건 3개를 확인한다(위 대원칙) — 셋 다 충족하지 않으면 브랜드는 Tier 0 에 남고 채널도 그대로다.
- 한국/일본 빌드 재분리(국가는 빌드 축이 아니다 — 서버는 항상 런타임 선택).
- Tier 1 승격 없이 브랜드 전용 패키지명/전용 APK 생성.
- 레거시 무접미 Android 채널 업로드 (**동결** — `lib/config/ota_config.dart` 주석 참조. Windows 는 반대로 무접미가 공통의 정본 채널이니 혼동 주의).
