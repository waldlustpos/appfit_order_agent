// BIXOLON USB 라벨 프린터(VID 0x1504) 존재 스캔 — Windows 전용.
//
// Android NativeMethodHandler 의 UsbManager VID 스캔과 등가. SetupAPI 로
// 현재 연결된 USB 장치 InstanceId 에 "VID_1504" 가 있는지만 본다 (~수 ms).
// 장치가 있을 때만 BXLLAPI ConnectPrinterEx 를 시도하므로
// hang-when-absent 리스크가 원천 제거된다.
//
// win32 패키지는 프로젝트 관례상 deferred import 로만 참조한다
// (printer_transport.dart 주석 참고 — Android 에서 native lookup 트리거 방지).
// 이 파일이 그 deferred 대상이다.

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// VID 0x1504(BIXOLON) USB 장치가 현재 연결돼 있는지. 실패 시 false.
Future<bool> isBixolonUsbPresent() => Isolate.run(_scanVid1504);

bool _scanVid1504() {
  try {
    final enumerator = 'USB'.toNativeUtf16();
    final devInfoData = calloc<SP_DEVINFO_DATA>()
      ..ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
    const idBufLen = 512;
    final idBuf = calloc<Uint16>(idBufLen);
    final required = calloc<Uint32>();
    try {
      final hDevInfo = SetupDiGetClassDevs(
        nullptr,
        enumerator,
        0,
        DIGCF_PRESENT | DIGCF_ALLCLASSES,
      );
      if (hDevInfo == INVALID_HANDLE_VALUE) return false;
      try {
        for (int i = 0;; i++) {
          if (SetupDiEnumDeviceInfo(hDevInfo, i, devInfoData) == 0) break;
          final ok = SetupDiGetDeviceInstanceId(
              hDevInfo, devInfoData, idBuf.cast<Utf16>(), idBufLen, required);
          if (ok == 0) continue;
          final id = idBuf.cast<Utf16>().toDartString();
          if (id.toUpperCase().contains('VID_1504')) return true;
        }
        return false;
      } finally {
        SetupDiDestroyDeviceInfoList(hDevInfo);
      }
    } finally {
      calloc.free(enumerator);
      calloc.free(devInfoData);
      calloc.free(idBuf);
      calloc.free(required);
    }
  } catch (_) {
    return false;
  }
}
