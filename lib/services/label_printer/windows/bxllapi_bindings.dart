// BIXOLON Windows Label SDK (BXLLAPI_x64.dll) 의 Dart FFI 바인딩.
//
// SDK 함수는 모두 undecorated 이름의 __stdcall export (x64 에서는 기본 ABI 와
// 동일). 콜백/핸들이 전혀 없는 완전 동기 API 이며 연결 상태는 DLL 프로세스
// 전역이다. DLL 은 CMake 가 runner exe 옆으로 복사하므로
// `DynamicLibrary.open('BXLLAPI_x64.dll')` 가 검색에 성공한다.
//
// 참고 헤더: external/bixolon/win64/BXLLApi.h (V3.10)
// 바인딩 스타일은 autoreplyprint_bindings.dart 를 미러.

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Native typedefs (FFI 호출용) — BOOL/int → Int32
// ---------------------------------------------------------------------------

typedef _SetShowMsgBoxNative = ffi.Int32 Function(ffi.Int32 bShow);
typedef _GetDllVersionNative = ffi.Int32 Function(ffi.Pointer<Utf8> buf);
typedef _ConnectPrinterExNative = ffi.Int32 Function(
    ffi.Int32 nInterface,
    ffi.Pointer<Utf8> szPortName,
    ffi.Int32 nBaudRate,
    ffi.Int32 nDataBits,
    ffi.Int32 nParity,
    ffi.Int32 nStopBits);
typedef _DisconnectPrinterNative = ffi.Int32 Function();
typedef _CheckStatusNative = ffi.Int32 Function();
typedef _GetPrinterDpiNative = ffi.Int32 Function();
typedef _ClearBufferNative = ffi.Int32 Function();
typedef _SetCharactersetNative = ffi.Int32 Function(
    ffi.Int32 ics, ffi.Int32 codepage);
typedef _SetConfigOfPrinterNative = ffi.Int32 Function(
    ffi.Int32 speed,
    ffi.Int32 density,
    ffi.Int32 orientation,
    ffi.Int32 autoCut,
    ffi.Int32 cuttingPeriod,
    ffi.Int32 backFeeding);
typedef _SetPaperNative = ffi.Int32 Function(
    ffi.Int32 hMargin,
    ffi.Int32 vMargin,
    ffi.Int32 paperWidth,
    ffi.Int32 paperLength,
    ffi.Int32 mediaType,
    ffi.Int32 offset,
    ffi.Int32 gapLength);
typedef _PrintDirectNative = ffi.Int32 Function(
    ffi.Pointer<Utf8> data, ffi.Int32 addCr);
typedef _PrintImageLibWNative = ffi.Int32 Function(ffi.Int32 x, ffi.Int32 y,
    ffi.Pointer<Utf16> path, ffi.Int32 dither, ffi.Int32 withRle);
typedef _PrintsNative = ffi.Int32 Function(
    ffi.Int32 labelSet, ffi.Int32 copies);

// ---------------------------------------------------------------------------
// Dart-facing typedefs (asFunction 결과)
// ---------------------------------------------------------------------------

typedef SetShowMsgBoxDart = int Function(int bShow);
typedef GetDllVersionDart = int Function(ffi.Pointer<Utf8> buf);
typedef ConnectPrinterExDart = int Function(int nInterface,
    ffi.Pointer<Utf8> szPortName, int baud, int dataBits, int parity, int stop);
typedef DisconnectPrinterDart = int Function();
typedef CheckStatusDart = int Function();
typedef GetPrinterDpiDart = int Function();
typedef ClearBufferDart = int Function();
typedef SetCharactersetDart = int Function(int ics, int codepage);
typedef SetConfigOfPrinterDart = int Function(int speed, int density,
    int orientation, int autoCut, int cuttingPeriod, int backFeeding);
typedef SetPaperDart = int Function(int hMargin, int vMargin, int paperWidth,
    int paperLength, int mediaType, int offset, int gapLength);
typedef PrintDirectDart = int Function(ffi.Pointer<Utf8> data, int addCr);
typedef PrintImageLibWDart = int Function(
    int x, int y, ffi.Pointer<Utf16> path, int dither, int withRle);
typedef PrintsDart = int Function(int labelSet, int copies);

/// BXLLAPI_x64.dll 의 함수 포인터 묶음. Windows 에서만 인스턴스화 가능.
///
/// Isolate.run 워커에서 tryGet() 하면 isolate 별 바인딩 인스턴스가 생기지만
/// DynamicLibrary.open 은 이미 로드된 모듈의 핸들을 재사용하고 DLL 연결 상태는
/// 프로세스 전역이므로 안전하다 (autoreplyprint 와 동일하게 검증된 패턴).
class BxlLapiBindings {
  BxlLapiBindings._() {
    if (!Platform.isWindows) {
      throw UnsupportedError('BXLLAPI SDK is Windows-only');
    }
    _dylib = ffi.DynamicLibrary.open('BXLLAPI_x64.dll');

    setShowMsgBox = _dylib
        .lookup<ffi.NativeFunction<_SetShowMsgBoxNative>>('SetShowMsgBox')
        .asFunction();
    getDllVersion = _dylib
        .lookup<ffi.NativeFunction<_GetDllVersionNative>>('GetDllVersion')
        .asFunction();
    connectPrinterEx = _dylib
        .lookup<ffi.NativeFunction<_ConnectPrinterExNative>>('ConnectPrinterEx')
        .asFunction();
    disconnectPrinter = _dylib
        .lookup<ffi.NativeFunction<_DisconnectPrinterNative>>(
            'DisconnectPrinter')
        .asFunction();
    checkStatus = _dylib
        .lookup<ffi.NativeFunction<_CheckStatusNative>>('CheckStatus')
        .asFunction();
    getPrinterDpi = _dylib
        .lookup<ffi.NativeFunction<_GetPrinterDpiNative>>('GetPrinterDPI')
        .asFunction();
    clearBuffer = _dylib
        .lookup<ffi.NativeFunction<_ClearBufferNative>>('ClearBuffer')
        .asFunction();
    setCharacterset = _dylib
        .lookup<ffi.NativeFunction<_SetCharactersetNative>>('SetCharacterset')
        .asFunction();
    setConfigOfPrinter = _dylib
        .lookup<ffi.NativeFunction<_SetConfigOfPrinterNative>>(
            'SetConfigOfPrinter')
        .asFunction();
    setPaper = _dylib
        .lookup<ffi.NativeFunction<_SetPaperNative>>('SetPaper')
        .asFunction();
    printDirect = _dylib
        .lookup<ffi.NativeFunction<_PrintDirectNative>>('PrintDirect')
        .asFunction();
    printImageLibW = _dylib
        .lookup<ffi.NativeFunction<_PrintImageLibWNative>>('PrintImageLibW')
        .asFunction();
    prints =
        _dylib.lookup<ffi.NativeFunction<_PrintsNative>>('Prints').asFunction();
  }

  late final ffi.DynamicLibrary _dylib;

  late final SetShowMsgBoxDart setShowMsgBox;
  late final GetDllVersionDart getDllVersion;
  late final ConnectPrinterExDart connectPrinterEx;
  late final DisconnectPrinterDart disconnectPrinter;
  late final CheckStatusDart checkStatus;
  late final GetPrinterDpiDart getPrinterDpi;
  late final ClearBufferDart clearBuffer;
  late final SetCharactersetDart setCharacterset;
  late final SetConfigOfPrinterDart setConfigOfPrinter;
  late final SetPaperDart setPaper;
  late final PrintDirectDart printDirect;
  late final PrintImageLibWDart printImageLibW;
  late final PrintsDart prints;

  static BxlLapiBindings? _instance;
  static bool _initFailed = false;
  static Object? _lastInitError;

  /// 싱글톤. Windows 가 아니면 lazy 로드 시점에 UnsupportedError.
  static BxlLapiBindings get instance => _instance ??= BxlLapiBindings._();

  /// 한 번만 시도하고 실패 시 null 반환. DLL 미배치/Windows 외 환경에서
  /// 호출 측이 isolate 를 죽이지 않고 우아하게 false 를 돌려줄 수 있게 한다.
  static BxlLapiBindings? tryGet() {
    if (_instance != null) return _instance;
    if (_initFailed) return null;
    if (!Platform.isWindows) {
      _initFailed = true;
      return null;
    }
    try {
      _instance = BxlLapiBindings._();
      return _instance;
    } catch (e) {
      _initFailed = true;
      _lastInitError = e;
      return null;
    }
  }

  static Object? get lastInitError => _lastInitError;
  static bool get initFailed => _initFailed;
  static bool get isAvailable => Platform.isWindows;
}
