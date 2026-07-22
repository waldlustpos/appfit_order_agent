# 릴리즈 / 배포 정책

코드 관리·배포 채널·롤아웃 절차의 정본입니다. 빌드 명령어·스크립트 상세는 [BUILD.md](BUILD.md), 채널/버전 도식은 [BUILD_VARIANTS.md](BUILD_VARIANTS.md) 참조. 코드 관리(브랜치·태그·핫픽스) 규율은 저장소 공통이며, 채널·롤아웃 절은 Android 기준입니다 — Windows 는 Sunmi App Store 와 무관한 단일 OTA 채널이므로 [BUILD.md](BUILD.md) Windows 절 참조.

## 대원칙: 아티팩트 1개, 채널 2개

- **코드는 단일 코드베이스·단일 main.** MHST 등 특정 브랜드 전용 포크/장수 브랜치를 만들지 않는다. 브랜드 차이는 `lib/utils/brand_registry.dart` 의 `BrandFeature` 로 런타임 분기한다.
- **빌드도 1개.** 한국/일본, MHST/그외 를 빌드로 나누지 않는다 (2026-07-09 변형 폐기 참조). 릴리즈당 APK 1개를 두 채널에 올린다.
- **분리는 유통 채널에서만** 한다:

| 채널 | 대상 함대 | 롤아웃 제어 |
| --- | --- | --- |
| OTA `_release` (`deploy_apk.sh` → Lightsail) | **MHST+Sunmi 를 제외한 모든 기기** — 비 Sunmi 안드로이드 전체 + `sunmiAppStoreUpdate` 가 **없는** 브랜드의 Sunmi 기기(TPCP/MATA/기타) + 수동 체크 | 없음 — 업로드 후 각 기기의 **다음 앱 시작(로그인 화면 진입) 시** 자동체크 ON 기기 전량에 반영, 비율 제어 불가 |
| Sunmi App Store (수동 업로드, gray 기기 타깃) | `sunmiAppStoreUpdate` 브랜드의 Sunmi 기기 (현재 **MHST** 900매장이 유일 대상) | gray 타깃으로 매장/기기 단위 단계 배포 가능 |

## 기기별 업데이트 정책 (코드에 이미 구현됨)

- **정책(2026-07-22 반전)**: `MHST + Sunmi = Sunmi App Store 채널(자동 OTA 체크 OFF)`, **그 외 모든 조합 = OTA 채널(자동 체크 ON)**. 이전엔 "Sunmi 전부 OFF + TPCP 만 ON 예외" 였으나, "전부 ON + MHST 만 OFF 예외" 로 뒤집혔다.
- 로그인 전 기본값: 자동 OTA 체크는 **Sunmi 기기 OFF, 그 외 ON** (`lib/services/preference_service.dart` `_initializeUpdateDefaults`). 이는 브랜드 미상 상태의 보수적 기본값(MHST 첫 실행 스푸리어스 OTA 방지)일 뿐이며, 최종 판정은 아래 로그인 재조정이 한다.
- **로그인 재조정**(`login_screen.dart`, `_login` 성공 분기): 설치 후 최초 로그인 1회, `sunmiAppStoreUpdate` 브랜드 + Sunmi 면 자동 체크 OFF, 그 외엔 ON 으로 세팅. 이후 사용자 수동 토글을 존중한다(`getUpdatePolicyReconciled` / `KEY_UPDATE_POLICY_MHST_SUNMI_V1` 마커). 자동·수동 로그인 공용 경로라 auto-login 기기도 다음 로그인 때 재조정된다.
  - **기존 fleet 마이그레이션**: 마커 문자열이 새 값이라, 기존 설치 기기 전부 다음 로그인 때 1회 재조정된다 — non-MHST Sunmi(기존 OFF)는 **ON(OTA)로 전환**, MHST+Sunmi 는 OFF 유지.
- **신규 브랜드 온보딩 결정 규칙**: "이 브랜드의 Sunmi 기기가 Sunmi App Store 관리 함대에 들어가는가?" — YES 면 `BrandFeature.sunmiAppStoreUpdate` 부여(→ OFF/앱스토어), NO 면 기능 없이 기본(→ ON/OTA).

## 릴리즈 절차

1. `pubspec.yaml` 버전 상승(versionCode `+n` 단조 증가) → 커밋 → **`git tag vX.Y.Z`** (어느 커밋이 몇 매장에 깔려 있는지 추적하는 유일한 수단).
2. 릴리즈 빌드: `flutter build apk --release --dart-define-from-file=.env` (또는 `./build_main.sh`).
3. 그 APK 를 **Sunmi App Store 에 업로드**, gray 로 소수 매장 canary 타깃.
4. canary 검증 후 gray 범위 확대.
5. 검증 완료 후 마지막에 `./deploy_apk.sh` 로 **OTA `_release` 갱신**. OTA 는 비율 제어가 없으므로 항상 맨 뒤에 놓는다.

### 채널 간 호환 불변식

- 두 채널 사이에서 기기가 어느 쪽 APK 로도 설치·업데이트될 수 있으려면 **같은 서명키 + 같은 versionCode** 여야 한다. Android 업데이트 요건은 동일 패키지 + 동일 서명 + versionCode ≥ 이므로 바이트 동일성까지는 필요 없다 — 5단계의 `deploy_apk.sh` 재빌드는 같은 커밋·같은 버전이면 문제없다.
- **두 업로드 사이에 커밋/버전을 바꾸지 말 것.** 수정이 필요해지면 버전을 올리고 1단계부터 다시 시작한다.
- 채널별 롤아웃 속도가 다르므로 함대에 버전 N/N-1 이 상시 공존한다. 서버 API·프로토콜 변경은 이 스큐를 전제로 한다.

## 핫픽스 절차

- Sunmi store 심사/gray 진행 중 긴급 수정이 필요할 때만: 배포된 `vX.Y.Z` 태그에서 `release/x.y` 브랜치 절단 → main 의 수정 커밋 cherry-pick → 버전 상승 → 새 태그 → 위 릴리즈 절차. 완료 후 브랜치는 정리한다 — **장수 브랜드 브랜치 금지.**

## 하지 말 것

- MHST 전용 패키지명/전용 APK 생성.
- 한국/일본 빌드 재분리.
- 브랜드별 OTA 채널 증설(`_mhst` 등) — 채널 수만큼 업로드 실수·버전 스큐 관리 비용이 늘어난다.
- 레거시 무접미 채널 업로드 (**동결** — `lib/config/ota_config.dart` 주석 참조).
