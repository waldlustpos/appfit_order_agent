// autoreplyprint SDK 의 Dart FFI 바인딩.
//
// SDK 함수는 모두 `extern "C"` 이며 핸들은 불투명 `void *` 이므로
// `Pointer<Void>` 로 표현한다. DLL 은 빌드 시 CMake 가 runner exe 와 같은 폴더로
// 복사하므로 `DynamicLibrary.open('autoreplyprint.dll')` 가 검색에 성공한다.
//
// 참고 헤더: external/autoreplyprint/win64/autoreplyprint.h

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// CP_OnPrinterStatusEvent 콜백 시그니처 (header line 460 부근).
//   void (*CP_OnPrinterStatusEvent)(void *handle,
//                                   const long long printer_error_status,
//                                   const long long printer_info_status,
//                                   void *private_data)
typedef CpOnPrinterStatusEventNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Int64 errorStatus,
  ffi.Int64 infoStatus,
  ffi.Pointer<ffi.Void> ctx,
);

// CP_OnPrinterPrintedEvent 콜백 시그니처 (header line 352).
//   void (*CP_OnPrinterPrintedEvent)(void *handle,
//                                    const unsigned int printer_printed_page_id,
//                                    void *private_data)
//
// autoReplyMode=1 + 이 콜백 등록이 함께 있어야 SDK 가 PagePrint ACK 처리를
// 자체 수행한다. 둘 중 하나라도 누락되면 CP_Pos_QueryPrintResult 가 timeout
// 하고 라벨이 한 장 인쇄된 상태에서 false 반환 → 호출자 재시도가 종이를 한 장
// 더 뽑는 사고가 발생한다 (appfit invariant: "동일 라벨 2장 인쇄").
typedef CpOnPrinterPrintedEventNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Uint32 printedPageId,
  ffi.Pointer<ffi.Void> ctx,
);

// ---------------------------------------------------------------------------
// Native typedefs (FFI 호출용)
// ---------------------------------------------------------------------------

typedef _LibraryVersionNative = ffi.Pointer<Utf8> Function();
typedef _PortEnumUsbNative = ffi.Uint32 Function(ffi.Pointer<ffi.Uint8> buffer,
    ffi.Uint32 cbBuf, ffi.Pointer<ffi.Uint32> cbNeeded);
typedef _PortOpenUsbNative = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<Utf8> name, ffi.Int32 autoReplyMode);
typedef _PortCloseNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);
typedef _PortIsOpenedNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);
typedef _PortIsConnectionValidNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle);

typedef _LabelEnableNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);
typedef _LabelCalibrateNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle);
typedef _LabelFeedNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);
typedef _LabelPageBeginNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle,
    ffi.Int32 x,
    ffi.Int32 y,
    ffi.Int32 width,
    ffi.Int32 height,
    ffi.Int32 rotation);
typedef _LabelPagePrintNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle, ffi.Int32 copies);
typedef _LabelDrawImageFromPixelsNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle,
    ffi.Int32 x,
    ffi.Int32 y,
    ffi.Pointer<ffi.Uint8> data,
    ffi.Uint32 dataLen,
    ffi.Int32 imgWidth,
    ffi.Int32 imgHeight,
    ffi.Int32 imgStride,
    ffi.Int32 imgFormat,
    ffi.Int32 binarization,
    ffi.Int32 compression);
typedef _LabelDrawImageFromDataNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle,
    ffi.Int32 x,
    ffi.Int32 y,
    ffi.Int32 dstw,
    ffi.Int32 dsth,
    ffi.Pointer<ffi.Uint8> data,
    ffi.Uint32 dataSize,
    ffi.Int32 binarization,
    ffi.Int32 compression);

typedef _PosResetPrinterNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle);
typedef _PosQueryPrintResultNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle, ffi.Uint32 timeoutMs);

typedef _PrinterGetStatusInfoNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle,
    ffi.Pointer<ffi.Int64> errStatus,
    ffi.Pointer<ffi.Int64> infoStatus,
    ffi.Pointer<ffi.Int64> timestampMs);
typedef _PrinterClearBufferNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle);
typedef _PrinterClearErrorNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> handle);

typedef _PrinterAddOnStatusNative = ffi.Int32 Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterStatusEventNative>> cb,
    ffi.Pointer<ffi.Void> ctx);
typedef _PrinterRemoveOnStatusNative = ffi.Int32 Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterStatusEventNative>> cb);

typedef _PrinterAddOnPrintedNative = ffi.Int32 Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterPrintedEventNative>> cb,
    ffi.Pointer<ffi.Void> ctx);
typedef _PrinterRemoveOnPrintedNative = ffi.Int32 Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterPrintedEventNative>> cb);

// ---------------------------------------------------------------------------
// Dart-facing typedefs (asFunction 결과)
// ---------------------------------------------------------------------------

typedef LibraryVersionDart = ffi.Pointer<Utf8> Function();
typedef PortEnumUsbDart = int Function(
    ffi.Pointer<ffi.Uint8> buffer, int cbBuf, ffi.Pointer<ffi.Uint32> cbNeeded);
typedef PortOpenUsbDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<Utf8> name, int autoReplyMode);
typedef PortCloseDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef PortIsOpenedDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef PortIsConnectionValidDart = int Function(ffi.Pointer<ffi.Void> handle);

typedef LabelEnableDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef LabelCalibrateDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef LabelFeedDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef LabelPageBeginDart = int Function(ffi.Pointer<ffi.Void> handle, int x,
    int y, int width, int height, int rotation);
typedef LabelPagePrintDart = int Function(
    ffi.Pointer<ffi.Void> handle, int copies);
typedef LabelDrawImageFromPixelsDart = int Function(
    ffi.Pointer<ffi.Void> handle,
    int x,
    int y,
    ffi.Pointer<ffi.Uint8> data,
    int dataLen,
    int imgWidth,
    int imgHeight,
    int imgStride,
    int imgFormat,
    int binarization,
    int compression);
typedef LabelDrawImageFromDataDart = int Function(
    ffi.Pointer<ffi.Void> handle,
    int x,
    int y,
    int dstw,
    int dsth,
    ffi.Pointer<ffi.Uint8> data,
    int dataSize,
    int binarization,
    int compression);

typedef PosResetPrinterDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef PosQueryPrintResultDart = int Function(
    ffi.Pointer<ffi.Void> handle, int timeoutMs);

typedef PrinterGetStatusInfoDart = int Function(
    ffi.Pointer<ffi.Void> handle,
    ffi.Pointer<ffi.Int64> errStatus,
    ffi.Pointer<ffi.Int64> infoStatus,
    ffi.Pointer<ffi.Int64> timestampMs);
typedef PrinterClearBufferDart = int Function(ffi.Pointer<ffi.Void> handle);
typedef PrinterClearErrorDart = int Function(ffi.Pointer<ffi.Void> handle);

typedef PrinterAddOnStatusDart = int Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterStatusEventNative>> cb,
    ffi.Pointer<ffi.Void> ctx);
typedef PrinterRemoveOnStatusDart = int Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterStatusEventNative>> cb);

typedef PrinterAddOnPrintedDart = int Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterPrintedEventNative>> cb,
    ffi.Pointer<ffi.Void> ctx);
typedef PrinterRemoveOnPrintedDart = int Function(
    ffi.Pointer<ffi.NativeFunction<CpOnPrinterPrintedEventNative>> cb);

/// autoreplyprint.dll 의 함수 포인터 묶음. Windows 에서만 인스턴스화 가능.
class AutoReplyPrintBindings {
  AutoReplyPrintBindings._() {
    if (!Platform.isWindows) {
      throw UnsupportedError('autoreplyprint SDK is Windows-only');
    }
    _dylib = ffi.DynamicLibrary.open('autoreplyprint.dll');

    libraryVersion = _dylib
        .lookup<ffi.NativeFunction<_LibraryVersionNative>>('CP_Library_Version')
        .asFunction();

    portEnumUsb = _dylib
        .lookup<ffi.NativeFunction<_PortEnumUsbNative>>('CP_Port_EnumUsb')
        .asFunction();
    portOpenUsb = _dylib
        .lookup<ffi.NativeFunction<_PortOpenUsbNative>>('CP_Port_OpenUsb')
        .asFunction();
    portClose = _dylib
        .lookup<ffi.NativeFunction<_PortCloseNative>>('CP_Port_Close')
        .asFunction();
    portIsOpened = _dylib
        .lookup<ffi.NativeFunction<_PortIsOpenedNative>>('CP_Port_IsOpened')
        .asFunction();
    portIsConnectionValid = _dylib
        .lookup<ffi.NativeFunction<_PortIsConnectionValidNative>>(
            'CP_Port_IsConnectionValid')
        .asFunction();

    labelEnableLabelMode = _dylib
        .lookup<ffi.NativeFunction<_LabelEnableNative>>(
            'CP_Label_EnableLabelMode')
        .asFunction();
    labelDisableLabelMode = _dylib
        .lookup<ffi.NativeFunction<_LabelEnableNative>>(
            'CP_Label_DisableLabelMode')
        .asFunction();
    labelCalibrateLabel = _dylib
        .lookup<ffi.NativeFunction<_LabelCalibrateNative>>(
            'CP_Label_CalibrateLabel')
        .asFunction();
    labelFeedLabel = _dylib
        .lookup<ffi.NativeFunction<_LabelFeedNative>>('CP_Label_FeedLabel')
        .asFunction();
    labelPageBegin = _dylib
        .lookup<ffi.NativeFunction<_LabelPageBeginNative>>('CP_Label_PageBegin')
        .asFunction();
    labelPagePrint = _dylib
        .lookup<ffi.NativeFunction<_LabelPagePrintNative>>('CP_Label_PagePrint')
        .asFunction();
    labelDrawImageFromPixels = _dylib
        .lookup<ffi.NativeFunction<_LabelDrawImageFromPixelsNative>>(
            'CP_Label_DrawImageFromPixels')
        .asFunction();
    labelDrawImageFromData = _dylib
        .lookup<ffi.NativeFunction<_LabelDrawImageFromDataNative>>(
            'CP_Label_DrawImageFromData')
        .asFunction();

    posResetPrinter = _dylib
        .lookup<ffi.NativeFunction<_PosResetPrinterNative>>(
            'CP_Pos_ResetPrinter')
        .asFunction();
    posQueryPrintResult = _dylib
        .lookup<ffi.NativeFunction<_PosQueryPrintResultNative>>(
            'CP_Pos_QueryPrintResult')
        .asFunction();

    printerGetStatusInfo = _dylib
        .lookup<ffi.NativeFunction<_PrinterGetStatusInfoNative>>(
            'CP_Printer_GetPrinterStatusInfo')
        .asFunction();
    printerClearBuffer = _dylib
        .lookup<ffi.NativeFunction<_PrinterClearBufferNative>>(
            'CP_Printer_ClearPrinterBuffer')
        .asFunction();
    printerClearError = _dylib
        .lookup<ffi.NativeFunction<_PrinterClearErrorNative>>(
            'CP_Printer_ClearPrinterError')
        .asFunction();

    printerAddOnStatus = _dylib
        .lookup<ffi.NativeFunction<_PrinterAddOnStatusNative>>(
            'CP_Printer_AddOnPrinterStatusEvent')
        .asFunction();
    printerRemoveOnStatus = _dylib
        .lookup<ffi.NativeFunction<_PrinterRemoveOnStatusNative>>(
            'CP_Printer_RemoveOnPrinterStatusEvent')
        .asFunction();

    printerAddOnPrinted = _dylib
        .lookup<ffi.NativeFunction<_PrinterAddOnPrintedNative>>(
            'CP_Printer_AddOnPrinterPrintedEvent')
        .asFunction();
    printerRemoveOnPrinted = _dylib
        .lookup<ffi.NativeFunction<_PrinterRemoveOnPrintedNative>>(
            'CP_Printer_RemoveOnPrinterPrintedEvent')
        .asFunction();
  }

  late final ffi.DynamicLibrary _dylib;

  late final LibraryVersionDart libraryVersion;
  late final PortEnumUsbDart portEnumUsb;
  late final PortOpenUsbDart portOpenUsb;
  late final PortCloseDart portClose;
  late final PortIsOpenedDart portIsOpened;
  late final PortIsConnectionValidDart portIsConnectionValid;

  late final LabelEnableDart labelEnableLabelMode;
  late final LabelEnableDart labelDisableLabelMode;
  late final LabelCalibrateDart labelCalibrateLabel;
  late final LabelFeedDart labelFeedLabel;
  late final LabelPageBeginDart labelPageBegin;
  late final LabelPagePrintDart labelPagePrint;
  late final LabelDrawImageFromPixelsDart labelDrawImageFromPixels;
  late final LabelDrawImageFromDataDart labelDrawImageFromData;

  late final PosResetPrinterDart posResetPrinter;
  late final PosQueryPrintResultDart posQueryPrintResult;

  late final PrinterGetStatusInfoDart printerGetStatusInfo;
  late final PrinterClearBufferDart printerClearBuffer;
  late final PrinterClearErrorDart printerClearError;

  late final PrinterAddOnStatusDart printerAddOnStatus;
  late final PrinterRemoveOnStatusDart printerRemoveOnStatus;

  late final PrinterAddOnPrintedDart printerAddOnPrinted;
  late final PrinterRemoveOnPrintedDart printerRemoveOnPrinted;

  static AutoReplyPrintBindings? _instance;
  static bool _initFailed = false;
  static Object? _lastInitError;

  /// 싱글톤. Windows 가 아니면 lazy 로드 시점에 UnsupportedError.
  static AutoReplyPrintBindings get instance =>
      _instance ??= AutoReplyPrintBindings._();

  /// 한 번만 시도하고 실패 시 null 반환. DLL 미배치/Windows 외 환경에서
  /// 호출 측이 isolate 를 죽이지 않고 우아하게 false 를 돌려줄 수 있게 한다.
  static AutoReplyPrintBindings? tryGet() {
    if (_instance != null) return _instance;
    if (_initFailed) return null;
    if (!Platform.isWindows) {
      _initFailed = true;
      return null;
    }
    try {
      _instance = AutoReplyPrintBindings._();
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
