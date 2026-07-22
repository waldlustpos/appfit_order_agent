---
name: project_deps_tier1_upgrade
description: "의존성 감사 + tier① 저위험 업그레이드 실행 완료(브랜치), tier②/③ 로드맵 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: a101d869-d4ef-4505-98f7-098d45aad9de
  modified: 2026-07-22T04:49:17.510Z
---

2026-07-22 의존성 버전 감사 후 tier① 저위험 묶음을 브랜치 `chore/deps-tier1-upgrade`(main 기준 5커밋, **미푸시**)에 실행. 감사 보고서: `C:\Users\Administrator\.claude\plans\dependencies-dazzling-wilkinson.md`(티어별 가치/공수/성능 근거).

**실행된 tier① (5커밋, 전부 analyze 0-error / 222 tests pass):**
1. 죽은 의존성 제거 — cloud_firestore·firebase_storage(import 0건, ~4.3MiB 네이티브 체인) + 미사용 dev 5종(freezed·freezed_annotation·json_serializable·json_annotation·mocktail). **firebase_core는 존치**(main.dart:166 initializeApp 사용).
2. minor-batch within-major(dio 5.10·http 1.6·audioplayers 6.7.1·secure_storage 10.3.1·table_calendar 3.2 등). qr(Dart 3.11)·audioplayers 6.8(Flutter 3.44) 제외.
3. Windows UI 트리오(window_manager 0.5.2·tray_manager 0.5.3·screen_retriever 0.2.2) + win32 5.15. **serial_port_win32는 1.4.2 유지**(tier②).
4. flutter_lints 2→6 **최소 적용**(사용자 선택) + launcher_icons 0.14.4 + dart fix.
5. slang 3→4([[reference_slang4_multifile_and_analyze_baseline]]).

**미완 후속(배포 전 필수)**: Windows 실기 스모크(bubble↔main·트레이 복원·COM 프린터), 로케일 전환 런타임 스모크(slang setLocaleSync는 컴파일로 안 잡히는 침묵 변경), Firebase 제거 release APK 크기 diff 확정.

**tier② 대기(각 독립 계획작업)**: Sentry 8→9(appfit_core 재태그 선행 + Windows crashpad), serial_port_win32 2.x(open/에러분류 재설계 + PR800/PL2303 실기검증), Riverpod 2→3(OrderMenuModel == 선수정 + 재시도 전역 옵트아웃 `ProviderScope(retry:(c,e)=>null)` + Notifier 필드 감사). **tier③ 보류**: device_info/package_info 13/10·win32 6(win32 5 고정 사슬 차단), connectivity_plus 7(AGP/Gradle/Kotlin 상향 편승), build_runner 2.6+(riverpod_generator 캡).
