---
name: project-order-output-audit-2026-07
description: "주문흐름·출력 누락/몰림 점검 완료(2026-07-07) — P1 3건 확인, 보고서 plans/output-joyful-noodle.md, 수정은 별도 세션 항목별 진행"
metadata: 
  node_type: memory
  type: project
  originSessionId: 220c5bba-3fe9-4c80-96d6-cda5ce8f9a32
---

2026-07-07 주문 흐름·출력 파이프라인 점검 완료 (기준: feat/log-upload-slack 8531292). 전체 보고서·로드맵: `~/.claude/plans/output-joyful-noodle.md` (사용자 승인됨).

**결정**: 이번 세션은 보고서만. **수정은 별도 세션에서 항목별 진행**. 출력 최종 실패 운영자 통지 채널은 **앱 내 배너/배지로 확정** (홈·KDS '출력 실패 N건' 배지 + 탭 시 해당 주문 이동).

**P1 3건 (코드 검증 완료)**:
1. 출력 최종 실패 무통지 — `onFinalFailure`(print_service.dart:101-110)는 파일로그만, "logger.e로 Sentry 캡처" 주석은 거짓(logger.dart에 Sentry 훅 없음). `printOrderReceipt`는 결과 버리고 return true. Sunmi 내장은 무조건 success(true)(NativeMethodHandler.java:299).
2. 크래시/재시작 시 미출력 잡 영구 유실 — 큐 전부 인메모리, "접수 PUT 성공~출력 완료" 사이 kill이면 재발행 트리거 없음(NEW만 재개). 유일한 구조 공백 → Tier 3 출력 저널(persist) 제안.
3. emit 루프 이중 기동 — `_startEmitLoop` 가드가 타이머 상태만 확인(order_queue_manager.dart:142-148), await 중 flush되면 병렬 체인 → 출력 순서 역전 재발 가능. 수정: `_isEmitting` 가드.

**Tier 1 즉시 수정 후보(승인된 로드맵)**: emit 가드 / onFinalFailure captureError / Sunmi 결과 전파 / labels.isEmpty 로그 / addReceiptReprint dedup.

**부수 발견 — 문서·인스펙터 카탈로그 구식**: 폴링 전용 경로(_processPollingNewOrders/getNewOrders)는 0c36c4e에서 제거되어 refreshOrders로 일원화됐는데 CLAUDE.md "자동접수 3경로"·order-flow-inspector 카탈로그가 옛 기술. Windows LabelPrintOrchestrator/LabelPrinterService 파일도 현재 없음(ARCHITECTURE.md·label-printer-inspector 구식). Android 라벨 PrintedEvent ACK 콜백 미등록(QueryPrintResult+PAPERNOFETCH 비콘이 완료 판정).

관련: [[project-refactor-audit-2026-06]], [[project-device-monitoring-design]] (배너/배지와 별개로 모니터링 연계 가능), [[project-label-ack-patch]]
