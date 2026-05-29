import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/brand_assets.dart';
import '../utils/logger.dart';
import 'platform_service.dart';
import 'preference_service.dart';
import 'printer_job_queue.dart';
import 'receipt_escpos_builder.dart';

// Windows 전용 transport (win32 + serial_port_win32 의존).
// Android 런타임에서는 절대 로드되지 않도록 deferred 로 import — 안 그러면
// win32 패키지의 static initializer 가 'kernel32.dll' lookup 을 시도해 실패한다.
// (실 출력은 [PrinterJobQueue] 가 [WindowsTransport] 로 직렬화하므로 본 import
// 는 isConnected / getAvailableComPorts 등 진단 API 용도로 남는다. PrintService
// 가 앱 시작 시 동일한 deferred 모듈을 로드해 transport 를 큐에 주입한다.)
import 'external_receipt_printer_windows.dart' deferred as win_transport;

/// 외부 영수증 프린터 출력의 플랫폼-무관 진입점.
///
/// 빌더([ReceiptEscPosBuilder.buildXxxBytes])가 만든 CP949 byte stream 을 양
/// 플랫폼에서 동일하게 사용한다. Windows 는 COM 우선 → Winspool 폴백, Android 는
/// MethodChannel `printReceiptBytes` → 네이티브 [UsbReceiptPrinter] 가 bulkTransfer
/// 로 송출. Java 측 EUC-KR 인코딩 로직을 걷어내 양 플랫폼 hex dump 가 1대1로 일치.
class ExternalReceiptPrinter {
  static Uint8List? _cachedLogoBytes;
  static String? _cachedLogoPath;
  static bool _cachedLogoIsNull = false;
  static bool _winTransportLoaded = false;

  Future<bool> printOrder(
    Map<String, dynamic> orderMap, {
    bool isCancel = false,
  }) async {
    final data = await ReceiptEscPosBuilder.buildOrderBytes(
      jsonOrder: orderMap,
      isCancel: isCancel,
      logoImageBytes: await loadReceiptLogoBytes(),
    );
    final displayNum = _displayNum(orderMap);
    return _sendBytes(data, '주문서_$displayNum');
  }

  Future<bool> printReceipt(
    Map<String, dynamic> orderMap, {
    bool isCancel = false,
  }) async {
    final data = await ReceiptEscPosBuilder.buildReceiptBytes(
      jsonOrder: orderMap,
      isCancel: isCancel,
      logoImageBytes: await loadReceiptLogoBytes(),
    );
    final displayNum = _displayNum(orderMap);
    return _sendBytes(data, '영수증_$displayNum');
  }

  /// 설정 화면 "테스트 출력" 버튼용. Windows / Android 동일 레이아웃.
  Future<bool> printTestPage() async {
    final pref = PreferenceService();
    final data = await ReceiptEscPosBuilder.buildTestPageBytes(
      comPort:
          pref.getComPortName() ?? (Platform.isAndroid ? 'USB' : 'WINSPOOL'),
      baudRate: pref.getComPortBaudRate(),
    );
    return _sendBytes(data, 'TEST');
  }

  /// (Android) UsbReceiptPrinter 의 bulkOut endpoint 확보 여부.
  /// Windows 는 COM 포트 enumerate / Winspool default 가용성으로 판단.
  Future<bool> isConnected() async {
    if (Platform.isAndroid) {
      try {
        final ok =
            await platform.invokeMethod<bool>('isExternalPrinterConnected');
        return ok == true;
      } catch (e, s) {
        logger.w('[ExternalReceiptPrinter] isExternalPrinterConnected 실패',
            error: e, stackTrace: s);
        return false;
      }
    }
    if (Platform.isWindows) {
      await _ensureWinTransport();
      return win_transport.isConnected();
    }
    return false;
  }

  /// (Android) UsbReceiptPrinter.discover() 재호출 — 권한 dialog 표시 / 재오픈.
  /// Windows 는 no-op (COM enumerate 는 매 출력 시점에 갱신).
  Future<void> reconnect() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('reconnectExternalPrinter');
    } on PlatformException catch (e, s) {
      logger.e('[ExternalReceiptPrinter] reconnectExternalPrinter 실패',
          error: e, stackTrace: s);
    }
  }

  // ---- internals ------------------------------------------------------

  Future<bool> _sendBytes(Uint8List data, String jobName) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      logger.w('[ExternalReceiptPrinter] 지원하지 않는 플랫폼 — 출력 생략');
      return false;
    }
    // 직접 transport 호출 대신 PrinterJobQueue 경유.
    // 큐가 직렬화 + 3회 backoff 재시도 + 최종 실패 시 onFinalFailure 콜백을 책임진다.
    // 플랫폼별 transport(Android: AndroidUsbTransport / Windows: WindowsTransport)
    // 는 [PrintService] 가 앱 시작 시 큐에 주입.
    final job = PrinterJob(
      bytes: data,
      jobName: jobName,
      kind: jobName.startsWith('영수증')
          ? 'receipt'
          : (jobName.startsWith('주문서') ? 'order' : 'misc'),
    );
    return PrinterJobQueue.instance.enqueue(job);
  }

  static Future<void> _ensureWinTransport() async {
    if (_winTransportLoaded) return;
    await win_transport.loadLibrary();
    _winTransportLoaded = true;
  }

  String _displayNum(Map<String, dynamic> orderMap) {
    final disp = orderMap['displayOrderNum'];
    if (disp is String && disp.isNotEmpty) return disp;
    final simple = orderMap['ordrSimpleId'];
    if (simple is String && simple.isNotEmpty) return simple;
    return '';
  }

  /// 현재 브랜드([BrandAssets.receiptLogoPath])의 영수증 로고 PNG 바이트를 로드.
  /// 로고가 없는 브랜드(path == null)는 null 반환. lazy-invalidation 캐싱(path 비교)
  /// 으로 번들 재로드는 브랜드당 1회. 외부 영수증 프린터 / Sunmi 내장 프린터가 공유.
  static Future<Uint8List?> loadReceiptLogoBytes() async {
    final String? targetPath = BrandAssets.receiptLogoPath;
    if (_cachedLogoPath != targetPath) {
      // 브랜드 전환(또는 첫 호출) — 캐시 무효화.
      _cachedLogoBytes = null;
      _cachedLogoIsNull = false;
      _cachedLogoPath = targetPath;
    }
    if (targetPath == null) {
      _cachedLogoIsNull = true;
      return null;
    }
    if (_cachedLogoBytes != null) return _cachedLogoBytes;
    if (_cachedLogoIsNull) return null;
    try {
      _cachedLogoBytes =
          (await rootBundle.load(targetPath)).buffer.asUint8List();
      return _cachedLogoBytes;
    } catch (e) {
      logger.w('[ExternalReceiptPrinter] 로고 로드 실패 ($targetPath), 계속 출력: $e');
      _cachedLogoIsNull = true;
      return null;
    }
  }
}
