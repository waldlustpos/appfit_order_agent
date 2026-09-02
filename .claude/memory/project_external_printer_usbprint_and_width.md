---
name: project-external-printer-usbprint-and-width
description: "Windows usbprint 직접 전송 경로 신설 + 영수증 폭 기종별 설정. 구현·테스트 완료, 실기기 검증 대기·미커밋 (2026-09-02)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 87b0ee85-0ceb-4dc5-ab40-7869e4275e55
  modified: 2026-09-02T05:19:00.000Z
---

POSBANK A8 이 Windows 에서 안 잡히던 문제와 출력물 6칸 밀림을 함께 처리했다.
구현·`flutter analyze` 클린·725 테스트 통과까지 끝났고 **실기기 검증 대기 / 미커밋**.

**진단 정본** (`pnputil /enum-devices /connected` 실측):
- PR800 = `USB\VID_0D28&PID_4C59` 복합(MI_00/MI_01) → CDC-ACM → usbser.sys → COM3
- POSBANK A8 = `USB\VID_0483&PID_A319` 단일 → **usbprint.inf 단독** → COM 포트 없음

**Why:** 두 경로는 우열이 아니라 **서로소 집합**이다 — 물리 RS-232 프린터는 usbprint 에
안 나오고, usbprint 바인딩 프린터는 CDC 가 없어 COM 을 안 만든다. 그리고 신·구 세대
차이가 아니다: USB Printer class 가 정통 표준이고 CDC 를 얹는 쪽이 RS-232 호환 계층이다.
Android 가 그냥 됐던 건 OS 드라이버가 안 끼고 앱이 엔드포인트를 직접 고르기 때문.

**How to apply:**
- 남은 것: Windows 실기 검증(A8 목록에 뜨는지 + G30 제외되는지 + 출력), Android APK 회귀
  (deferred 규칙 위반은 Android 런타임에서만 드러난다), 눈금자로 A8 폭 최종 확인, 커밋.
- **기본 폭 42 를 48 로 되돌리지 말 것.** 크게 잡으면 출력이 밀려 망가지고 작게 잡으면
  여백만 남는다 → 모르는 기종은 여백 쪽으로 실패해야 한다. 넓은 기종만 `knownPrinterColumns`
  (VID:PID → 컬럼) 에 등재한다. 현재 `0D28:4C59` → 48 하나.
- **usbprint 경로는 Winspool 금지에 저촉되지 않는다** — 근거 3조건(스풀러 미경유 / 채택은
  ESC/POS 응답 받은 장치만 / 라벨 VID 제외)이 무너지면 그때는 저촉. [[project-store-printer-topology]]
- ESC/POS 에 컬럼 수 질의는 **없다**(`GS W` 쓰기 전용). 자동 판별 시도하지 말 것 —
  VID:PID 테이블 + 눈금자(`buildWidthRulerBytes`)가 유일한 수단.
- 상세는 `docs/PRINTER_FLOW.md` §2.2/§2.3 과 `.claude/agents/external-receipt-printer-inspector.md`
  W3/W3b 에 있다. [[reference-win32-deferred-import]] [[feedback-ffi-isolate-boxing]]
