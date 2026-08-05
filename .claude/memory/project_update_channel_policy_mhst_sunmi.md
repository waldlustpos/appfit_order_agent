---
name: project_update_channel_policy_mhst_sunmi
description: "Android 자동업데이트 채널 정책 반전 — MHST+Sunmi만 앱스토어(OTA OFF), 그 외 전부 OTA(ON)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 118abc6d-c915-4daf-ae65-06f64ffa1018
  modified: 2026-08-05T06:25:47.972Z
---

2026-07-22 Android 업데이트 채널 정책을 **반전**했다.

- 새 정책: `MHST + Sunmi = Sunmi App Store 채널(자동 OTA 체크 OFF)`, **그 외 모든 조합 = OTA 채널(자동 체크 ON)**.
- 옛 정책: "Sunmi 전부 OFF + TPCP 만 로그인 시 ON 오버라이드"(= `autoUpdateForce`). 이걸 "전부 ON + MHST 만 OFF 예외"로 뒤집음.

**분기 축 2개**(모델별 분기는 없음 — 제조사 `sunmi` 문자열만 봄):
1. 기기 제조사 == `sunmi` (D3/D2s 모델 무관)
2. 브랜드 capability `BrandFeature.sunmiAppStoreUpdate` (현재 **MHST 단독**, `brand_registry.dart`)

**게이트 구조** (채널 URL 자체는 브랜드/기기 분기 없음 — 단일 `_release`. 분기는 "자동 체크 ON/OFF"만):
- `preference_service._initializeUpdateDefaults` (최초 1회, 로그인 전): sunmi→OFF, 그 외→ON. **보수적 기본값일 뿐**(MHST 첫 실행 스푸리어스 OTA 방지). 일부러 유지.
- `login_screen._login` 성공 분기 (수동·자동 로그인 공용): 설치 후 최초 로그인 1회, `isSunmi && brand.has(sunmiAppStoreUpdate)` → OFF, 그 외 → ON. **최종 판정은 여기**. 이후 사용자 수동 토글 존중.
- 1회성 마커: `getUpdatePolicyReconciled` / `KEY_UPDATE_POLICY_MHST_SUNMI_V1` (구 `KEY_UPDATE_TPCP_OVERRIDE_DONE` 대체).

**기존 fleet 마이그레이션**: 마커 문자열이 새 값이라 기존 설치 기기 전부 다음 로그인 때 1회 재조정 → non-MHST Sunmi(기존 OFF)가 **ON(OTA)로 전환**. 이게 이번 변경의 실질 효과.

**신규 브랜드 규칙**: Sunmi App Store 관리 함대면 `sunmiAppStoreUpdate` 부여(→OFF), 아니면 미부여(→ON/OTA).

변경 파일: brand_registry.dart(enum 의미 반전+TPCP→MHST 이동), login_screen.dart, preference_service.dart, brand_registry_test.dart(16 pass), docs(RELEASE/ARCHITECTURE/AS-IS). analyze 새 에러 0. 커밋 `5e7004a`로 main에 병합 완료(확인 2026-08-05) — 작성 당시 "미커밋" 메모는 낡은 정보였음. 실기기 배포 여부는 `/deploy-android` 이력 별도 확인 필요. 이중 채널 배경은 [[feedback_com_startup_retry_scope]] 아닌 RELEASE.md 참조.
