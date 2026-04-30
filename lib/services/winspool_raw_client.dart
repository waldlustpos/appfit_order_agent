import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../utils/logger.dart';

/// Windows 프린터 스풀러(RAW 모드)로 ESC/POS 바이트를 전송하는 얇은 래퍼.
///
/// 사용자가 제어판에서 USB 영수증 프린터를 등록하고 (드라이버/generic text-only
/// 모두 가능), 그 프린터 이름을 지정하면 바이트가 그대로 장치로 흘러간다.
class WinspoolRawClient {
  /// 시스템 기본 프린터 이름. 없으면 null.
  static String? getDefaultPrinterName() {
    final sizeNeeded = calloc<Uint32>()..value = 0;
    try {
      // 첫 호출: 필요한 버퍼 크기 요청
      GetDefaultPrinter(nullptr, sizeNeeded);
      if (sizeNeeded.value == 0) return null;

      final buf = calloc<Uint16>(sizeNeeded.value);
      try {
        final ok = GetDefaultPrinter(buf.cast(), sizeNeeded);
        if (ok == 0) return null;
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(sizeNeeded);
    }
  }

  /// EnumPrintersW(Level 2, PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS)
  /// 로컬 설치 프린터 + 네트워크 연결 프린터 목록.
  static List<String> listPrinters() {
    const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    const level = 2; // PRINTER_INFO_2

    final pcbNeeded = calloc<Uint32>();
    final pcReturned = calloc<Uint32>();
    try {
      final sizeCheck = EnumPrinters(flags, nullptr, level, nullptr, 0, pcbNeeded, pcReturned);
      logger.d('[WinspoolRawClient] EnumPrinters size check: ok=$sizeCheck, needed=${pcbNeeded.value}');

      if (pcbNeeded.value == 0) {
        logger.w('[WinspoolRawClient] No printers found (pcbNeeded=0)');
        return const [];
      }

      final buf = calloc<Uint8>(pcbNeeded.value);
      try {
        final ok = EnumPrinters(
          flags,
          nullptr,
          level,
          buf,
          pcbNeeded.value,
          pcbNeeded,
          pcReturned,
        );

        final count = pcReturned.value;
        logger.d('[WinspoolRawClient] EnumPrinters result: ok=$ok, count=$count, err=${GetLastError()}');

        if (ok == 0) {
          logger.e('[WinspoolRawClient] EnumPrinters failed: err=${GetLastError()}');
          return const [];
        }

        if (count == 0) {
          logger.w('[WinspoolRawClient] EnumPrinters returned 0 printers');
          return const [];
        }

        // PRINTER_INFO_2 구조체 배열에서 pPrinterName 만 추출.
        final arr = buf.cast<PRINTER_INFO_2>();
        final result = <String>[];
        for (var i = 0; i < count; i++) {
          final name = (arr + i).ref.pPrinterName;
          if (name != nullptr) {
            final printerName = name.toDartString();
            result.add(printerName);
            logger.d('[WinspoolRawClient] Found printer: $printerName');
          }
        }
        logger.i('[WinspoolRawClient] Total printers enumerated: ${result.length}');
        return result;
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(pcbNeeded);
      calloc.free(pcReturned);
    }
  }

  /// 지정 프린터로 RAW 바이트 전송. 성공 여부 반환.
  static bool sendRaw(String printerName, String jobName, Uint8List data) {
    if (printerName.isEmpty || data.isEmpty) return false;

    final pName = printerName.toNativeUtf16();
    final pJob = jobName.toNativeUtf16();
    final pType = 'RAW'.toNativeUtf16();
    final hPrinterPtr = calloc<HANDLE>();
    final di = calloc<DOC_INFO_1>();
    Pointer<Uint8>? dataBuf;
    final written = calloc<Uint32>();

    try {
      if (OpenPrinter(pName, hPrinterPtr, nullptr) == 0) {
        logger.e('OpenPrinter 실패: $printerName (err=${GetLastError()})');
        return false;
      }
      final hPrinter = hPrinterPtr.value;

      di.ref
        ..pDocName = pJob
        ..pOutputFile = nullptr
        ..pDatatype = pType;

      final jobId = StartDocPrinter(hPrinter, 1, di.cast());
      if (jobId == 0) {
        logger.e('StartDocPrinter 실패 (err=${GetLastError()})');
        ClosePrinter(hPrinter);
        return false;
      }

      if (StartPagePrinter(hPrinter) == 0) {
        logger.e('StartPagePrinter 실패 (err=${GetLastError()})');
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return false;
      }

      dataBuf = calloc<Uint8>(data.length);
      dataBuf.asTypedList(data.length).setAll(0, data);

      final ok = WritePrinter(hPrinter, dataBuf.cast(), data.length, written);
      final success = ok != 0 && written.value == data.length;
      if (!success) {
        logger.e(
            'WritePrinter 실패: written=${written.value}/${data.length} err=${GetLastError()}');
      }

      EndPagePrinter(hPrinter);
      EndDocPrinter(hPrinter);
      ClosePrinter(hPrinter);
      return success;
    } finally {
      calloc.free(pName);
      calloc.free(pJob);
      calloc.free(pType);
      calloc.free(hPrinterPtr);
      calloc.free(di);
      if (dataBuf != null) calloc.free(dataBuf);
      calloc.free(written);
    }
  }
}
