---
name: reference-windows-cmake-install-prefix-pinned
description: "낡은 CMakeCache 는 CMAKE_INSTALL_PREFIX 를 runner/Release 절대경로로 굳혀, debug/profile 번들까지 Release 폴더로 install 한다"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 3bb78a7e-e989-4d47-92f1-290d28d56d1a
  modified: 2026-08-27T12:34:59.476Z
---

정상 상태의 `build/windows/x64/CMakeCache.txt` 는

```
CMAKE_INSTALL_PREFIX:PATH=$<TARGET_FILE_DIR:appfit_order_agent>
```

처럼 **제네레이터 표현식**이라 구성별로 갈린다. 그런데 캐시가 오래 굴러가면 이 값이
`.../build/windows/x64/runner/Release` **절대경로로 굳어버린 상태**가 된다. 한 번 굳으면
`CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 가 false 라
[windows/CMakeLists.txt](windows/CMakeLists.txt) 의 `set(... FORCE)` 가 다시 안 돌아 스스로
안 풀린다. 2026-08-27 실측.

굳었을 때의 증상 — **구성 불문 모든 INSTALL 이 `runner/Release` 로 간다**:

- `flutter build windows --debug` → `runner/Release/appfit_order_agent.exe` 가 Debug 바이너리로
  덮이고 `runner/Release/data/flutter_assets/kernel_blob.bin`(debug JIT 87MB)이 release
  `app.so` 옆에 생긴다. Debug/Release exe 의 MD5 가 같아지는 것으로 확인된다.
- `flutter build windows --profile` → `runner/Profile/` 에 exe 만 있고 `data/` 가 아예 없다.
- 즉 `runner/Debug`·`runner/Profile` 번들은 낡은 채 남고 exe 만 새로 링크된다.

**왜 중요한가**: 포장 규칙이 `Release\*` 재귀라 오염이 그대로 설치본/OTA 에 실린다. 커밋
e6b9e75 / 642f55f 의 "다른 브랜드 잔재 제거" 스윕은 `exe/exp/lib/pdb` 만 지우고 `data/` 는
안 건드리므로 debug kernel_blob 오염은 못 막는다. 그 커밋들이 고친 브랜드 오염도 뿌리는 같다.

**How to apply**: `grep CMAKE_INSTALL_PREFIX build/windows/x64/CMakeCache.txt` 로 확인한다.
절대경로면 `CMakeCache.txt` + `CMakeFiles` + `runner/{Debug,Profile,Release}` 를 지우고 재빌드하면
표현식으로 복구된다(= build_windows.ps1 이 브랜드 전환 때 쓰는 부분 wipe + 산출물 정리).
`flutter clean` 은 쓰지 말 것 — `firebase_cpp_sdk_windows_*.zip`(806MB)과 `extracted/` 까지 날아간다.
같은 wipe 가 [[project-windows-debug-firebase-crash]] 도 해결한다.
