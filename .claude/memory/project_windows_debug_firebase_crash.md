---
name: project-windows-debug-firebase-crash
description: Windows Debug 가 firebase_core 등록에서 크래시하면 코드가 아니라 낡은 CMake 생성 상태다 — 캐시 wipe 후 재빌드로 해결
metadata: 
  node_type: memory
  type: project
  originSessionId: 3bb78a7e-e989-4d47-92f1-290d28d56d1a
  modified: 2026-08-27T12:34:29.349Z
---

2026-08-27, VS Code 의 `mammoth (debug)` 실행이 실패했다. 툴이 뱉은 것은
`Error connecting to the service protocol … 원격 컴퓨터가 네트워크 연결을 거부했습니다` 였지만
**네트워크/DDS 문제가 아니라 앱 프로세스가 기동 ~5초 뒤 죽어서** 디버거가 못 붙은 것이다.

크래시(minidump + PDB 심볼라이즈): access violation `0xC0000005`, **write to 0x0**

```
wWinMain → Win32Window::Create → FlutterWindow::OnCreate (flutter_window.cpp:27)
  → RegisterPlugins (generated_plugin_registrant.cc:23)
    → FirebaseCorePlugin::RegisterWithRegistrar (firebase_core_plugin.cpp:46)
      → firebase::app_common::RegisterLibrary → LibraryRegistry::RegisterLibrary
        → std::string::assign → char_traits::assign   ★
```

**진짜 원인은 firebase 가 아니라 `build/windows/x64` 의 낡은 CMake 생성 상태였다.**
`CMakeCache.txt` + `CMakeFiles` + `runner/{Debug,Profile,Release}` 를 지우고 재빌드하니 정상
기동했다. 결정적 증거 — 같은 소스인데 **exe 크기가 2.15MB → 3.49MB** 로 바뀌었다. 이전 링크가
불완전했던 것이다. 곁가지 증상은
[[reference-windows-cmake-install-prefix-pinned]] 참조.

**배제된 원인** (다시 의심하지 말 것):
- 커밋 e085ddc / c2dad2d 의 `main.cpp`(단일 인스턴스 뮤텍스 개편) — 머지 이전 버전으로 되돌려
  빌드해도 동일 크래시. 스택상 뮤텍스 블록은 엔진 시작 전에 끝나 `RegisterPlugins` 로 갈 수 없다.
- firebase_core 버전 회귀 — pubspec.lock 상 2026-02-27 이후 불변.
- `_ITERATOR_DEBUG_LEVEL` 불일치 — `FAILIFMISMATCH` 지시자가 우리 obj 와 firebase Debug lib
  둘 다 `=2` 로 일치.
- Debug 구성 자체의 결함 — 정리 후 Debug 는 잘 돈다.

**진단 중 두 번 헛짚은 판별자** (같은 함정 반복 금지):
1. 로그의 `업데이트 체크: current=…, latest=…` 는 release 표식이 **아니다**. 설정 화면 진입도
   `WindowsUpdateService().checkForUpdate()` 를 부른다([settings_screen.dart](lib/screens/settings_screen.dart)).
   release 판별은 그 줄이 **기동 직후**에 있는지로 해야 한다 — `runStartupUpdateFlow()` 는
   `kReleaseMode` 에서만 runApp 이전에 돈다.
2. `logger.i('[Main] Debug 모드 …')` 는 [logger.dart](lib/utils/logger.dart) 화이트리스트
   (warning 이상 / `[SYSTEM]` `[PLATFORM]` `[UI_ACTION]` 등 태그)에 안 걸려 **파일에 안 남는다.**
   로그 파일에서 이 줄을 찾아 debug 여부를 판정하려 하지 말 것.

**How to apply**: Windows 러너가 플러그인 등록 구간에서 죽으면 플러그인/코드를 파기 전에 먼저
빌드 트리를 재생성한다. `flutter clean` 은 쓰지 말 것(806MB firebase SDK 재다운로드) —
캐시 부분 wipe 로 충분하다. fresh configure 뒤 **첫 INSTALL 은 MSB3073 으로 실패하고 2회차에
성공**한다([[project-windows-standalone-first-install-pass-fails]]).
