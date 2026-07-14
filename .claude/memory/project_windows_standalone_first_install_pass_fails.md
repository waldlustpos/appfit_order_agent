---
name: project_windows_standalone_first_install_pass_fails
description: "standalone Windows 빌드는 fresh configure 직후 첫 INSTALL 패스가 실패, 2차(증분) 패스는 성공. build_windows.ps1은 exit code 미검사라 깨진 산출물을 아카이브함."
metadata: 
  node_type: memory
  type: project
  originSessionId: 613115fe-aa48-43ca-b790-c84c4690200b
---

`build_windows.ps1 -Variant standalone` 를 **clean(=fresh CMake configure) 직후** 돌리면 첫 빌드의 INSTALL 단계가 `MSB3073` 로 실패한다. 실제 원인은 cmake_install 의 generator expression `$<TARGET_FILE_DIR:appfit_order_agent_standalone>` 가 `No target "appfit_order_agent_standalone"` — fresh configure 직후 runner 타깃이 install 평가 시점에 아직 안 풀리는 first-pass 비결정성(플러그인 subproject 다수 + firebase_cpp_sdk 의 낮은 cmake_minimum_required 정책 스코프 영향 추정). exe 자체는 만들어지지만 `data/`(app.so·flutter_assets·icudtl.dat)·`flutter_windows.dll`·플러그인 DLL 복사가 전부 누락된다. **같은 build/windows 에 두 번째(증분) 패스를 돌리면 INSTALL 이 성공**해 정상 산출물이 나온다. update/default 변형이 이걸 거의 안 겪는 건 그 build dir 가 좀처럼 wipe 되지 않아 fresh-configure 상태가 드물기 때문.

치명적 2차 버그: [build_windows.ps1] 은 `flutter build` 의 `$LASTEXITCODE` 를 검사하지 않고 `Test-Path $buildOutput`(폴더 존재) 만 확인한다. 첫 패스가 INSTALL 실패해도 exe 가 있어 폴더는 존재 → "빌드 완료" 오판 → [archive_windows.ps1] 이 **깨진 산출물(exe+VC런타임만, ~16MB)을 그대로 ZIP 아카이브**한다. 정상 zip 은 ~27MB(app.so 11MB + flutter_windows.dll 등 포함). `$ErrorActionPreference="Stop"` 은 네이티브 exe 비정상 종료코드를 못 잡으므로 `if ($LASTEXITCODE -ne 0) { exit 1 }` 명시 필요(+ 가능하면 INSTALL 실패 시 1회 자동 재빌드).

**해결됨(2026-06-29):** [build_windows.ps1] 와 [build_installer.ps1] 둘 다 `Invoke-FlutterWindowsBuild`(콘솔로 출력만 흘리고 호출부에서 전역 `$LASTEXITCODE` 직접 판정 — 함수가 return 하면 빌드 출력이 반환값에 섞이는 함정 주의) + `Test-BuildArtifactComplete`(`flutter_windows.dll` + `data\app.so` 존재 검사) + 첫 패스 실패/불완전 시 같은 build dir 로 1회 자동 재빌드 + 그래도 불완전하면 `exit 1`(아카이브/설치본 생성 차단) 적용. build_installer 는 원래 exit code 는 봤지만 무결성 검사·재시도는 없었음.

**Why:** 깨진 OTA/배포 산출물이 조용히 아카이브/배포될 수 있음. **How to apply:** standalone fresh 빌드는 산출물에 `data/app.so` + `flutter_windows.dll` 존재를 항상 검증; 첫 INSTALL MSB3073 면 같은 build dir 로 재빌드(이제 스크립트가 자동). 관련: [[project_dual_variant_build]] [[reference_windows_toolchain_quirks]]
