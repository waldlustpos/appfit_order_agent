---
name: project-fleet-remote-control
description: Fleet 원격화면제어 확장 공수 분석 — 자체 구현 대신 Sunmi MDM + MeshCentral 권고. 결정 게이트 실험 미실행
metadata: 
  node_type: memory
  type: project
  originSessionId: b0723b0d-37f6-4c17-bd8a-1b4b6d21e4c4
  modified: 2026-08-03T04:47:47.588Z
---

2026-08-03 분석. 전제는 **무인 원격 점검 + 기기 전체 화면 + 별도 에이전트 허용 + Android/Windows 동시**(사용자가 명시 선택). 분석 문서 정본은 `~/.claude/plans/fleet-crystalline-rabbit.md`.

**결론: 자체 구현 90~148 PD(1인 5~7개월) vs 기성품 조합 13~22 PD. 기성품 권고.**
경로 B = Sunmi MDM Remote Assistance(Android) + MeshCentral(Apache-2.0 셀프호스팅, Windows) + Fleet 대시보드는 디렉터리·감사 계층.

**Why:** 앱이 평범한 사용자 앱(자체 키스토어 서명, `DevicePolicyManager` 0건, Sunmi SDK는 프린터·스캐너뿐)이고 `targetSdk 35`라, Android 14+의 "캡처 세션마다 사용자 동의"를 정식으로 우회할 수단이 없다. 유일한 실무 우회인 `adb shell appops set <pkg> PROJECT_MEDIA allow`는 **기기별 물리 접촉 1회**가 영구 전제가 되어, 이미 매장에 나간 기기를 전부 방문해야 한다 — 이게 코드보다 비싼 진짜 킬러다. 반면 Sunmi는 D3 MINI 포함 현행 기종에 Unattended Mode를 시스템 레벨로 이미 제공한다.

**How to apply:**
- **아직 아무것도 실행하지 않았다.** 다음 행동은 코딩이 아니라 **결정 게이트 실험 3개**(각 반나절): ① Sunmi Partner Portal에서 D3 MINI 무인 접속 성립 여부(+D2s_KDS도 되는지, 한국 계정 조건·과금) ② Lightsail에 MeshCentral + Windows POS 에이전트로 화면제어·파일다운로드 ③ 위 `appops` 한 줄이 D3 MINI 실기에서 동의창 없이 통하는지. ③이 실패하면 자체 구현안 전체가 그 자리에서 폐기된다.
- **보안 개편이 원격제어보다 먼저다.** 현 대시보드는 workers.dev 퍼블릭 URL + 공유 비밀번호 1개(`appfit-fleet/src/auth.ts`)이고 `/api/login`에 레이트리밋이 없다. 여기에 원격제어를 얹으면 비밀번호 하나가 전 매장 POS 장악 권한이 된다. 경로 A/B 무관하게 선행.
- 재사용 가능한 것: 기기 인벤토리·명령 큐·`DeviceIdentityService`. **통째로 신규인 것: 실시간 전송 계층** — 현행은 15~60초 폴링이고 백엔드에 DO/WebSocket/R2가 전무하며, AppFit 소켓은 수신 전용이라 못 쓴다.
- Android 파일탐색은 어떤 구현을 쓰든 `/sdcard` 범위가 천장이다(타 앱 `/data/data` 불가). `MANAGE_EXTERNAL_STORAGE`는 이미 선언·구현돼 있다.
- 경로 B 채택 시 앱 코드 변경은 사실상 `order_agent_fleet_snapshot.dart`에 `sunmiSn`/`meshNodeId` 필드 2개뿐 — **appfit_core는 건드리지 않는다**(태그 릴리즈 왕복 회피).

관련: [[project-fleet-monitoring]], [[reference-fleet-scaling-limits]], [[reference-cloudflare-worker-traps]]
