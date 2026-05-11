import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/logger.dart';
import 'com_port_print_service.dart';
import 'preference_service.dart';
import 'receipt_escpos_builder.dart';
import 'winspool_raw_client.dart';

/// Windows 영수증/주문서/테스트 페이지 출력.
///
/// 실제 ESC/POS 명령 빌드는 [ReceiptEscPosBuilder] 가 담당하고, 본 서비스는
/// 캐싱·송신(COM 우선, Winspool 폴백)·로깅만 책임진다. Android 외부 영수증
/// 출력 경로([PrintService] → MethodChannel `printReceiptSegments`)도 같은
/// 빌더를 공유하여 두 플랫폼 출력물이 단일 소스에서 결정된다.
class WindowsPrintService {
  static Uint8List? _cachedLogoImageBytes;

  Future<bool> printOrderFromJson(String orderJson, bool isCancel) async {
    final printerName = _resolvePrinter();
    if (printerName == null) {
      logger.e('[WinPrint] 프린터 이름이 설정되지 않아 주문서 출력 생략');
      return false;
    }

    Map<String, dynamic> jsonOrder;
    try {
      jsonOrder = jsonDecode(orderJson) as Map<String, dynamic>;
    } catch (e) {
      logger.e('[WinPrint] 주문 JSON 파싱 실패: $e');
      return false;
    }

    final logoBytes = await _loadLogoBytes();
    final data = await ReceiptEscPosBuilder.buildOrderBytes(
      jsonOrder: jsonOrder,
      isCancel: isCancel,
      logoImageBytes: logoBytes,
    );

    final displayNum =
        (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
            ? jsonOrder['displayOrderNum'] as String
            : (jsonOrder['ordrSimpleId'] as String? ?? '');

    return _send(data, printerName, '주문서_$displayNum',
        errLabel: 'COM 포트 출력 실패');
  }

  Future<bool> printReceiptFromJson(String orderJson, bool isCancel) async {
    final printerName = _resolvePrinter();
    if (printerName == null) {
      logger.e('[WinPrint] 프린터 이름이 설정되지 않아 영수증 출력 생략');
      return false;
    }

    Map<String, dynamic> jsonOrder;
    try {
      jsonOrder = jsonDecode(orderJson) as Map<String, dynamic>;
    } catch (e) {
      logger.e('[WinPrint] 영수증 JSON 파싱 실패: $e');
      return false;
    }

    final logoBytes = await _loadLogoBytes();
    final data = await ReceiptEscPosBuilder.buildReceiptBytes(
      jsonOrder: jsonOrder,
      isCancel: isCancel,
      logoImageBytes: logoBytes,
    );

    final displayNum =
        (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
            ? jsonOrder['displayOrderNum'] as String
            : (jsonOrder['ordrSimpleId'] as String? ?? '');

    return _send(data, printerName, '영수증_$displayNum',
        errLabel: 'COM 포트 영수증 출력 실패');
  }

  /// 설정 UI "테스트 출력" 버튼용. Windows 스풀러 경로 (COM 미설정 시 호출).
  Future<bool> printTestPage() async {
    final printerName = _resolvePrinter();
    if (printerName == null) return false;
    final data = await ReceiptEscPosBuilder.buildTestPageBytes(
      comPort: PreferenceService().getComPortName() ?? 'WINSPOOL',
      baudRate: PreferenceService().getComPortBaudRate(),
    );
    return WinspoolRawClient.sendRaw(printerName, '테스트', data);
  }

  /// COM 포트가 설정돼 있으면 그쪽으로 먼저 시도, 실패하면 Windows 스풀러로 폴백.
  Future<bool> _send(
    Uint8List data,
    String printerName,
    String jobName, {
    required String errLabel,
  }) async {
    final comPort = PreferenceService().getComPortName();
    if (comPort != null && comPort.isNotEmpty) {
      try {
        final comOk = await ComPortPrintService.sendRaw(
          data,
          comPort: comPort,
          baudRate: PreferenceService().getComPortBaudRate(),
        );
        if (comOk) return true;
      } catch (e) {
        logger.w('[WinPrint] $errLabel: $e, Windows 스풀러로 폴백');
      }
    }
    return WinspoolRawClient.sendRaw(printerName, jobName, data);
  }

  /// 로고 PNG 를 캐싱 로드. 로드 실패 시 null 반환(로고 없이 출력).
  Future<Uint8List?> _loadLogoBytes() async {
    if (_cachedLogoImageBytes != null) return _cachedLogoImageBytes;
    try {
      _cachedLogoImageBytes = (await rootBundle.load('assets/images/logo.png'))
          .buffer
          .asUint8List();
      return _cachedLogoImageBytes;
    } catch (e) {
      logger.w('[WinPrint] 로고 로드 실패, 계속 출력: $e');
      return null;
    }
  }

  String? _resolvePrinter() {
    final configured = PreferenceService().getWindowsPrinterName();
    if (configured != null && configured.isNotEmpty) return configured;
    return WinspoolRawClient.getDefaultPrinterName();
  }
}
