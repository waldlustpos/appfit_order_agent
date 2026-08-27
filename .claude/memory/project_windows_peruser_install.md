---
name: project-windows-peruser-install
description: "Windows per-user 설치 전환 — 구현·검증·main 병합 완료, 매머드 195 설치본 배포 진행 중 (OTA 채널 갱신 미완)"
metadata: 
  node_type: memory
  type: project
  originSessionId: c3baa59a-e7d6-4562-9fae-547e4cb390c0
  modified: 2026-08-27T02:45:20.413Z
---

Defender 오탐(`Trojan:Win32/Bearfoos.A!ml`) 대응으로 Windows 설치 위치를
`C:\Program Files` → `%LOCALAPPDATA%\Programs` per-user 로 전환. 2026-08-27
구현·양 브랜드 실기 검증·`main` 병합·push 완료(`783998e`, `e6b9e75`).
설계·검증 결과·발견 결함은 `docs/WINDOWS_PERUSER_INSTALL.md` 6·8절이 정본.

**진행 상태 (2026-08-27 기준)**
- 매머드 `3.0.0+195` 설치본 생성 완료 (SHA256 `25C0002F…`)
- 사내 기기 1대 설치 완료 — Defender 예외 2경로 정상 등록 확인
- **남은 것**: Windows 매장 4곳 원격 설치 → 그 다음 `deploy_windows.ps1
  -Brand mammoth -SkipBuild` 로 OTA 채널을 195 로 갱신
- 배포 당시 채널: mammoth 194 / common 191 (Android 는 195 배포됨)

**순서가 중요하다**
1. 설치본을 4곳 모두 설치한 **뒤에** 채널을 올린다. 먼저 올리면 아직 방문 안 한
   매장이 Program Files 설치본 그대로 OTA 를 받고, 그때 점주 화면에 **예정에 없던
   UAC 프롬프트**가 뜬다(거부해도 `:fail → :launch` 로 구버전이 계속 도니 장애는
   아님).
2. `build_installer.ps1` → `deploy_windows.ps1 -SkipBuild` 사이에 **`flutter build`
   나 다른 브랜드 빌드를 돌리면 안 된다** — Release 폴더가 바뀌어 설치본/OTA exe
   해시 통일이 깨진다(Defender 평판은 해시 단위).

**기억할 사실 2가지 (문서에도 있지만 배포 판단에 직결)**
- **기존 매장은 OTA 로 자동 이관되지 않는다.** OTA 는 계속 Program Files 설치본을
  갱신할 뿐이므로, per-user 로 옮기려면 새 설치본을 한 번 실행해야 한다.
- **`:fail → :launch` 는 롤백이 아니다.** robocopy 는 rc≥8 에서도 일부 파일을 이미
  복사한 뒤라 구/신이 섞인다. 보장 범위는 "앱이 다시 뜬다"까지.

관련: [[reference-defender-exclusion-query]] · [[feedback-concurrent-deploy-version-race]] ·
[[reference-windows-toolchain-quirks]]
