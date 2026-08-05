---
name: reference-win32-deferred-import
description: win32 패키지를 새로 쓸 때는 top-level import 금지 — Android kernel32.dll lookup 크래시. 반드시 별도 파일 + deferred as.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 74594566-8476-4a14-ad1a-6837e8a4f3f9
  modified: 2026-08-05T07:01:05.607Z
---

`package:win32/win32.dart`를 아무 파일에나 top-level `import`하면 안 됨 — Android 런타임에서 win32 → kernel32.dll lookup이 크래시를 일으킴. 이 프로젝트는 Android+Windows 단일 코드베이스라 Android에서도 그 파일이 (다른 무관한 코드를 통해서라도) import 그래프에 걸리면 죽는다.

**규칙**: win32 의존 코드는 항상 leaf 파일로 분리하고, 그 파일을 참조하는 쪽에서 `import '...' deferred as alias;`로만 로드. 실제 호출 전에 `await alias.loadLibrary();` 필수. 선례: `com_port_descriptor.dart`(주석 자체가 이 규칙의 근거), `external_receipt_printer_windows.dart` ← `print_service.dart`/`external_receipt_printer.dart`(`deferred as win_transport`), `bixolon_usb_presence_windows.dart`. 신규 추가: `windows_timezone_service.dart` ← `platform_service.dart`(`deferred as win_timezone`), [project_login_timezone_env_hint](project_login_timezone_env_hint.md)에서 씀.

주의: `escpos_builder.dart`/`com_port_print_service.dart`는 top-level에서 non-deferred로 win32를 import하지만 안전한 이유는 이 두 파일 자체가 오직 `external_receipt_printer_windows.dart`를 통해서만(즉 deferred 체인 안에서만) 도달되기 때문 — 파일 자체의 import 문만 보고 규칙 준수 여부를 판단하면 안 되고, **그 파일이 Android 쪽 import 그래프에서 도달 가능한지**를 확인해야 함.

**적용 시점**: win32 API를 새로 쓰는 모든 작업(레지스트리 읽기, SetupAPI, 시리얼포트 등) 전에 이 패턴부터 확인.
