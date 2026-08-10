---
name: project-label-recovery-deadlock
description: 라벨 복구대기 8분 정지 원인=info 0x10(NoPaperCanceled) 미해제. 떼기대기 루프가 루트. 수정 완료·실기기 검증 대기 (2026-08-10)
metadata: 
  node_type: memory
  type: project
  originSessionId: 6042ee9b-9d49-4c06-80fb-98a3ec52faf4
  modified: 2026-08-10T03:46:45.590Z
---

실매장(PAIK00002)에서 **용지를 갈았는데도 라벨 큐가 8분간 정지** → 운영자가 재출력 7번 누르다
앱 강제 종료. 앱 재시작으로만 풀렸다.

**원인은 error status 와 info status 의 비대칭.** 복구대기 탈출 조건은
`noPaper(0x04) || coverUp(0x80) || noPaperCanceled(0x10)` 인데, 앞 둘은 error 이고 **0x10만 info** 다.
`ERROR 해제` 로그는 `error_status == 0` 만 보므로 **"해제됐다고 찍혔는데 대기는 계속되는"** 상태가
성립한다. 0x10 은 용지를 갈아도 안 내려가고, 그걸 내릴 유일한 계기(다음 인쇄 명령)는 그 루프 뒤에
있다 — **대기가 자신을 깨울 사건을 스스로 봉쇄**한다. timeout·interrupt 발생원 둘 다 없어 앱 강제
종료가 유일한 탈출구였다.

**루트 원인은 한 단계 앞**: 떼기대기 루프가 `while (lastInfoPaperNoFetch)` 로 0x20만 봤다.
떼기대기 중 용지가 떨어지면 펌웨어가 보류 페이지를 취소하며 0x20↓+0x10↑ 하는데, 그 하강을
"운영자가 뗐다"로 오독해 **나오지도 않은 라벨을 성공 처리(누락)하고 0x10을 다음 라벨에 물려줬다.**
완료 대기 루프에는 그 가드가 이미 있었고 떼기대기 루프에만 빠져 있었다.

**Why (진단 교훈 3가지):**
1. **"평소엔 잘 되는데 가끔 안 된다"는 조건 분기를 찾으라는 신호.** 평소 용지 교체가 정상 복구된
   것은 0x10이 안 섰기 때문이고, 그 차이가 곧 답이었다.
2. **재현 실패는 방법이 틀린 게 아니라 트리거를 안 건드린 것.** 테스트 기기 재현 2회 모두 앞 라벨이
   평범한 `출력끝` 이었다 — "떼기대기 중 용지 소진" 이라는 순서를 만들어야 재현된다.
3. **진행 로그가 상태를 안 찍으면 현장 판별이 불가능하다.** `복구대기중 elapsed=60s` 가 8분간
   반복됐지만 비트가 없어 원인을 로그로 좁힐 수 없었다. 이번에 `noPaper=/cover=/canceled=/action=`
   추가.

**How to apply:** 브랜치 `fix/network-degradation-resilience` (미커밋). `LabelPrinter.java` 에
떼기대기 0x10 가드 + 복구대기 active clear(`ClearPrinterError`/`ClearPrinterBuffer`/`ResetPrinter`)
+ 1.5초 강제 break. **Windows 에는 이 수정이 이미 있었다**(`windows_label_printer_backend.dart`
`sawUserAction` 패턴) — 플랫폼 비대칭이 곧 결함의 위치였다([[project-label-printer-platform-divergence]]).
`docs/ARCHITECTURE.md` 의 "Android 는 펌웨어가 비트 자동 해제(active clear 불필요)" 는 이번에
반증돼 수정했다.

함께 넣은 것: 재출력 dedup 이 무음이었어서 로그 추가(클릭 7건에 인쇄진입 0건이 설명 안 되던 원인).

**UI 배너는 만들었다가 제거했다.** 복구 상태를 네이티브 volatile → MethodChannel → 2초 폴링 →
상단 앰버 띠([[project-network-degradation-2026-08]] 의 `SyncStatusBanner` 패턴)로 띄워 실기기에서
동작까지 확인했으나, **운영자는 어차피 프린터의 라벨지 상태를 직접 본다**는 판단으로 걷어냈다
(배너·모델·i18n 3로캘·폴링·MethodChannel·volatile 필드 전부). 대기 사유는 네이티브 파일 로그
(`복구대기 진입 [...]` + `elapsed=Ns noPaper=/cover=/canceled=/action=`)에 이미 남으므로 진단력은
그대로다. **UI를 없앨 때는 그 UI만을 위해 만든 배관까지 함께 지울 것** — 남기면 죽은 코드가 된다.
되살릴 일이 생기면 git 이력에 있다.

**재현 절차**: ① 라벨 1장 인쇄 후 떼지 않기 → `떼기대기` 확인 ② **그 상태에서** 용지 제거
③ 다음 주문으로 `복구대기 진입` 유도 ④ 용지 넣고 커버 닫기.

**2026-08-10 재현 검증 완료** — 이 절차로 정확히 재현됐고 수정이 의도대로 동작했다.
결정적 증거는 `복구대기 진입 … canceled=false` (수정 전이라면 true 로 물려받아 데드락).
라벨 누락 0(취소된 장이 재시도로 인쇄), 중복 0.

재현 로그가 드러낸 잉여 동작 2가지도 함께 고쳤다:
- **정상 복구에서도 active clear 가 한 번 발동했다.** `while` 조건 재평가는 다음 iteration 이라
  세 비트가 다 내려간 순간에도 stuck 검사가 한 발 먼저 실행된다 → 조건에 `canceled` 를 추가.
  (Windows 원본에도 같은 잉여가 있을 것으로 보인다.)
- **`canceled` 단독 진입은 여전히 무한 대기였다.** cover/noPaper 가 처음부터 false 라
  `sawUserAction` 이 영영 참이 안 된다 → `canceledOnlyEntry` 로 조치 관측을 건너뛰게 함.
  조건을 좁히면 그 조건이 배제한 경로를 반드시 다시 확인할 것.
