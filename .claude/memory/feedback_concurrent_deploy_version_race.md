---
name: feedback_concurrent_deploy_version_race
description: 배포 확인 직후 pubspec.yaml 버전이 다른 세션에 의해 계속 바뀌는 레이스 — 실행 직전 재확인 필수
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5c1576cc-79ff-4c2f-81d5-dd7db4188a4d
  modified: 2026-08-25T08:04:42.394Z
---

`/deploy-android` 1단계에서 서버/pubspec 버전을 확인하고 사용자 승인까지 받았는데, 실제 `./deploy_apk.sh` 실행 전 짧은 시간 사이에 다른 세션(다른 터미널의 Claude Code 등)이 pubspec.yaml의 build-number 를 계속 바꾸고 이미 배포까지 마친 사례가 3회 관측됨(2026-08-03 MHST 브랜드 이미지 작업, 2026-08-04 라벨 QR 버그 수정 배포, 2026-08-25 mammoth 연속 배포). 한 번은 확인 시점 174 → 배포 후 175 → 잠시 후 조회 173 → 177 로 값이 출렁였고, 서버는 내가 배포하지 않은 176 을 이미 서빙 중이었음. 2026-08-25 건은 mammoth 를 192 로 배포 직후 서버 재조회가 193(내가 올리지 않은 값)이었고, 사용자가 "194로 올렸음, mammoth만 재배포" 라고 알려줘 재확인 후 194 로 정상 진행 — 승인 재획득 절차가 실제로 사고를 막은 사례.

**Why:** 이 레포는 Android/Windows 버전 정본이 pubspec.yaml 하나([CLAUDE.md](../../../../Documents/GitHub/appfit_order_agent/CLAUDE.md) "버전 정본" 규칙)라, 동시에 다른 세션이 build-number 를 올리고 배포하면 사용자에게 보여준 "현재 서버 버전 → 업데이트할 버전" 표가 실행 시점엔 이미 stale 해질 수 있음. 그대로 실행하면 다운그레이드 배포나 서로 다른 세션의 코드 변경이 뒤섞인 APK 가 나갈 위험.

**How to apply:** 1단계 승인을 받은 뒤에도, `./deploy_apk.sh` 실행 **직전**에 `grep "^version:" pubspec.yaml` 로 한 번 더 재확인한다. 값이 승인 시점과 다르거나 확인 중에도 계속 바뀌면(버전이 요동치면) 바로 실행하지 말고 [[project_mhst_brand_image_2026_08]] 처럼 사용자에게 동시 세션 여부를 물어본다(AskUserQuestion). 사용자가 "지금 상태로 재확인 후 진행"을 선택하면 재확인된 안정값으로 진행.
