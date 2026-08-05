// Windows 표준 시간대 키 이름 조회 — win32 레지스트리 API 직접 의존.
//
// win32 패키지는 프로젝트 관례상 deferred import 로만 참조한다(Android 에서
// win32 → kernel32.dll lookup 크래시 회피 — com_port_descriptor.dart 주석 참고).
// 이 파일이 그 deferred 대상이며, platform_service.dart 에서만 로드된다.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 현재 Windows 표준 시간대의 레지스트리 키 이름(예: "Korea Standard Time",
/// "Tokyo Standard Time")을 읽는다. 이 값은 OS 표시 언어와 무관한 원본 키
/// 이름이라(TIME_ZONE_INFORMATION.StandardName 과 달리 지역화되지 않음)
/// 국가 판정에 안전하게 쓸 수 있다. 조회 실패 시 null.
String? getWindowsTimezoneKeyName() {
  final subKey =
      'SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation'.toNativeUtf16();
  final valueName = 'TimeZoneKeyName'.toNativeUtf16();
  final hKeyPtr = calloc<IntPtr>();
  const bufferSize = 256;
  final dataBuffer = calloc<Uint8>(bufferSize);
  final dataSize = calloc<Uint32>()..value = bufferSize;
  final typePtr = calloc<Uint32>();
  try {
    final openStatus =
        RegOpenKeyEx(HKEY_LOCAL_MACHINE, subKey, 0, KEY_READ, hKeyPtr);
    if (openStatus != 0) return null;
    final hKey = hKeyPtr.value;
    try {
      final queryStatus = RegQueryValueEx(
        hKey,
        valueName,
        nullptr,
        typePtr,
        dataBuffer,
        dataSize,
      );
      if (queryStatus != 0) return null;
      return dataBuffer.cast<Utf16>().toDartString();
    } finally {
      RegCloseKey(hKey);
    }
  } finally {
    calloc.free(subKey);
    calloc.free(valueName);
    calloc.free(hKeyPtr);
    calloc.free(dataBuffer);
    calloc.free(dataSize);
    calloc.free(typePtr);
  }
}
