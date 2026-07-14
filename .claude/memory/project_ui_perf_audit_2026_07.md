---
name: project-ui-perf-audit-2026-07
description: "T2_mini_s UI 성능 감사 완료(2026-07-02) — P1~P6 코드 수정 적용, 남은 것은 실기기 측정 + Impeller A/B + 죽은 자산 정리"
metadata: 
  node_type: memory
  type: project
  originSessionId: b3524b68-d117-4d8b-8850-d1e990ef5d3a
---

2026-07-02 T2_mini_s(Android 7.1, 2GB RAM, Mali-T7xx) 대상 UI 성능 감사 완료. 45개 에이전트 스캔+적대적 검증 결과 **앱은 이미 잘 최적화돼 있었고**(의심 33건 중 26건 반박 — RepaintBoundary/select/builder/배칭 기적용), 확정 이슈만 수정 적용:

- P1(핵심): `Order` notifier에 `updateShouldNotify(prev,next) => prev != next` 오버라이드 — 무변경 폴링(연결 60s/끊김 15s)마다 발생하던 전체 watcher 통지·리빌드 차단. characterization 테스트 그룹 (f)로 고정.
- P2~P6: 앱바 소켓 아이콘 Consumer 분리, BlinkState ==/updateShouldNotify+배지 select, 시계 DateFormat 로캘 캐시, 드로어 아이콘/브랜드 로고 cacheWidth, SoundService setVolume 변경 시에만 호출.

수정분은 2026-07-02 main 에 커밋 완료: perf(ui) 4f5822a, chore(assets) login-bg.png 삭제 bc18db2 (~670KB 절감), feat(store-status) 오더 토글 복원 dc523f3. 미푸시.

**남은 후속 과제 (미실행)**:
1. T2_mini_s 실기기 측정: `flutter run --profile` + DevTools 타임라인, `adb shell dumpsys gfxinfo co.kr.waldlust.order.receive`. 시나리오: KDS 방치 5분 / 소켓 끊김 15s 폴링 / 소켓 burst(앱바 시계 롱프레스) / 카드 가로 스크롤.
2. Impeller A/B: AndroidManifest `EnableImpeller` true/false 두 빌드 비교 — Mali-T7xx에서 코드 수정보다 큰 지렛대일 가능성. 측정 없이 판단 금지.

감사 상세와 반박된 항목 목록(재론 방지)은 plans/ui-kind-zephyr.md 참고. [[project-refactor-audit-2026-06]] 의 "전면 리팩토링 불필요" 결론과 일치.
