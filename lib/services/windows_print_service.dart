import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../utils/logger.dart';
import 'com_port_print_service.dart';
import 'escpos_builder.dart';
import 'preference_service.dart';
import 'winspool_raw_client.dart';

/// SUNMI/Posbank 안드로이드 측 PrintUtil.java 의 출력 포맷을 Windows + USB
/// 영수증 프린터에서 동일하게 재현한다.
class WindowsPrintService {
  static final _priceFmt = NumberFormat('#,###');
  static Uint8List? _cachedLogoImageBytes;

  /// 주방용(ORDER) — 금액 없이 메뉴/수량만.
  /// Android `PrintUtil.printOrderFromJson` + Sunmi 유사 포맷
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

    final b = EscPosStreamBuilder()
      ..init()
      ..setAlign(EscPos.alignCenter);

    if (isCancel) {
      b
        ..textLn('[취소주문서]')
        ..ln();
    }

    b
      ..boldOn()
      ..setSize(EscPos.fontTall);
    final displayNum = (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
        ? jsonOrder['displayOrderNum'] as String
        : (jsonOrder['ordrSimpleId'] as String? ?? '');
    b
      ..textLn('주문번호: $displayNum')
      ..setSize(EscPos.fontNormal)
      ..boldOff()
      ..ln();

    final userName = jsonOrder['userName'] as String?;
    if (userName != null && userName.isNotEmpty && userName != 'null') {
      b
        ..boldOn()
        ..setSize(EscPos.fontTall)
        ..textLn('$userName님')
        ..setSize(EscPos.fontNormal)
        ..boldOff();
    }
    final kioskId = jsonOrder['kioskId'] as String?;
    if (kioskId != null && kioskId.isNotEmpty && kioskId != 'null') {
      b.textLn('키오스크: $kioskId');
    }
    b.ln();

    b
      ..setAlign(EscPos.alignLeft)
      ..textLn(jsonOrder['storeName'] as String? ?? '')
      ..textLn('[일시] : ${jsonOrder['ordrDtm'] as String? ?? ''}')
      ..textLn(EscPos.separatorLine(48))
      ..text(EscPos.padRight('메뉴', 38))
      ..text(EscPos.padLeft('수량', 10))
      ..ln()
      ..textLn(EscPos.separatorLine(48));

    final menuList = jsonOrder['ordrPrdList'];
    if (menuList is List) {
      for (final m in menuList) {
        if (m is! Map) continue;
        final menuName = m['prdNm'] as String? ?? '';
        final menuCount = (m['ordrCnt'] as num?)?.toInt() ?? 0;
        final countStr = isCancel ? '-$menuCount' : '$menuCount';

        b
          ..text(EscPos.padRight(menuName, 38))
          ..text(EscPos.padLeft(countStr, 10))
          ..ln();

        final options = m['optPrdList'];
        if (options is List && options.isNotEmpty) {
          for (final o in options) {
            if (o is! Map) continue;
            final optName = o['optPrdNm'] as String? ?? '';
            final optCount = (o['optPrdCnt'] as num?)?.toInt() ?? 0;
            final optCountStr = isCancel ? '-$optCount' : '$optCount';
            b
              ..text(EscPos.padRight(' -$optName', 38))
              ..text(EscPos.padLeft(optCountStr, 10))
              ..ln();
          }
          b.textLn(EscPos.separatorLine(48));
        }
        b.ln();
      }
    }

    final memo = jsonOrder['ordrMemo'] as String? ?? '';
    if (memo.isNotEmpty) {
      b
        ..ln()
        ..setAlign(EscPos.alignCenter)
        ..textLn(memo)
        ..setAlign(EscPos.alignLeft);
    }

    b
      ..setAlign(EscPos.alignCenter)
      ..ln();
    await _addLogoIfAvailable(b);
    b
      ..ln()
      ..ln()
      ..cut();

    final data = b.build();

    // COM 포트 설정이 있으면 COM 포트로 먼저 시도
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
        logger.w('[WinPrint] COM 포트 출력 실패: $e, Windows 스풀러로 폴백');
      }
    }

    // Windows 스풀러로 출력
    return WinspoolRawClient.sendRaw(
      printerName,
      '주문서_$displayNum',
      data,
    );
  }

  /// 고객용(RECEIPT) — 금액/세금/총액 포함.
  /// Sunmi 유사 포맷: fontWide 메뉴명, ━ 구분선, 다양한 폰트 크기
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

    final b = EscPosStreamBuilder()
      ..init()
      ..setAlign(EscPos.alignCenter);

    if (isCancel) {
      b
        ..textLn('[취소영수증]')
        ..ln();
    }

    b
      ..boldOn()
      ..setSize(EscPos.fontTall);
    final displayNum = (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
        ? jsonOrder['displayOrderNum'] as String
        : (jsonOrder['ordrSimpleId'] as String? ?? '');
    b
      ..textLn('주문번호 : $displayNum')
      ..setSize(EscPos.fontNormal)
      ..boldOff()
      ..ln()
      ..setAlign(EscPos.alignLeft)
      ..textLn(jsonOrder['storeName'] as String? ?? '')
      ..textLn('[일시]   : ${jsonOrder['ordrDtm'] as String? ?? ''}')
      ..textLn(EscPos.separatorLine(48))
      ..text(EscPos.padRight('메뉴', 28))
      ..text(EscPos.padLeft('수량', 10))
      ..text(EscPos.padLeft('금액', 10))
      ..ln()
      ..textLn(EscPos.separatorLine(48));

    final menuList = jsonOrder['ordrPrdList'];
    if (menuList is List) {
      for (final m in menuList) {
        if (m is! Map) continue;
        final menuName = m['prdNm'] as String? ?? '';
        final menuCount = (m['ordrCnt'] as num?)?.toInt() ?? 0;
        final menuPrice = (m['prdPrc'] as num?)?.toDouble() ?? 0.0;
        final total = (menuPrice * menuCount).toInt();
        final countStr = isCancel ? '-$menuCount' : '$menuCount';
        final amountStr = isCancel
            ? '-${_priceFmt.format(total)}'
            : _priceFmt.format(total);

        b
          ..text(EscPos.padRight(menuName, 28))
          ..text(EscPos.padLeft(countStr, 10))
          ..text(EscPos.padLeft(amountStr, 10))
          ..ln();

        final options = m['optPrdList'];
        if (options is List && options.isNotEmpty) {
          for (final o in options) {
            if (o is! Map) continue;
            final optName = o['optPrdNm'] as String? ?? '';
            final optCount = (o['optPrdCnt'] as num?)?.toInt() ?? 0;
            final optPrice = (o['optPrdPrc'] as num?)?.toDouble() ?? 0.0;
            final optTotal = (optPrice * optCount).toInt();
            final optCountStr = isCancel ? '-$optCount' : '$optCount';
            final optAmountStr = isCancel
                ? '-${_priceFmt.format(optTotal)}'
                : _priceFmt.format(optTotal);

            b
              ..text(EscPos.padRight(' -$optName', 28))
              ..text(EscPos.padLeft(optCountStr, 10))
              ..text(EscPos.padLeft(optAmountStr, 10))
              ..ln();
          }
          b.textLn(EscPos.separatorLine(48));
        }
      }
    }

    b
      ..setAlign(EscPos.alignRight)
      ..textLn('과세금액: ${jsonOrder['exceptTaxPrice'] ?? '0'}')
      ..textLn('부 가 세: ${jsonOrder['taxPrice'] ?? '0'}')
      ..setAlign(EscPos.alignLeft)
      ..textLn(EscPos.separatorLine(48));

    final orderPrice = jsonOrder['ordrPrc']?.toString() ?? '0';
    final discountPrice = jsonOrder['discPrc']?.toString() ?? '0';
    final paymentPrice = jsonOrder['payPrc']?.toString() ?? '0';

    b
      ..text(EscPos.padRight('주문금액 : ', 38))
      ..text(EscPos.padLeft(orderPrice, 10))
      ..ln()
      ..text(EscPos.padRight('할인금액 : ', 38))
      ..text(EscPos.padLeft(
          discountPrice == '0' ? '0' : '-$discountPrice', 10))
      ..ln()
      ..boldOn()
      ..text(EscPos.padRight('결제금액 : ', 38))
      ..text(EscPos.padLeft(paymentPrice, 10))
      ..ln()
      ..boldOff();

    final memo = jsonOrder['ordrMemo'] as String? ?? '';
    if (memo.isNotEmpty) {
      b
        ..ln()
        ..setAlign(EscPos.alignCenter)
        ..textLn(memo)
        ..setAlign(EscPos.alignLeft);
    }

    b
      ..setAlign(EscPos.alignCenter)
      ..ln();
    await _addLogoIfAvailable(b);
    b
      ..ln()
      ..ln()
      ..ln()
      ..cut();

    final data = b.build();

    // COM 포트 설정이 있으면 COM 포트로 먼저 시도
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
        logger.w('[WinPrint] COM 포트 영수증 출력 실패: $e, Windows 스풀러로 폴백');
      }
    }

    // Windows 스풀러로 출력
    return WinspoolRawClient.sendRaw(
      printerName,
      '영수증_$displayNum',
      data,
    );
  }

  /// 설정 UI 에서 "테스트 출력" 버튼용.
  Future<bool> printTestPage() async {
    final printerName = _resolvePrinter();
    if (printerName == null) return false;
    final b = EscPosStreamBuilder()
      ..init()
      ..setAlign(EscPos.alignCenter)
      ..setSize(EscPos.fontLarge)
      ..textLn('프린터 테스트')
      ..setSize(EscPos.fontNormal)
      ..textLn(DateTime.now().toString())
      ..ln()
      ..textLn('한글 출력 확인 ABC 0123')
      ..textLn(EscPos.separatorLine(42))
      ..ln();
    await _addLogoIfAvailable(b);
    b
      ..ln()
      ..ln()
      ..ln()
      ..cut();
    return WinspoolRawClient.sendRaw(printerName, '테스트', b.build());
  }

  /// 로고 PNG를 async로 로드하여 빌더에 추가.
  /// 첫 로드 시 메모리에 캐싱하여 반복 호출 시 빠르게 처리.
  Future<void> _addLogoIfAvailable(EscPosStreamBuilder builder) async {
    try {
      // 캐시가 없으면 로고 PNG 로드
      if (_cachedLogoImageBytes == null) {
        _cachedLogoImageBytes = (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
      }
      if (_cachedLogoImageBytes != null) {
        await builder.addImageRaster(_cachedLogoImageBytes!);
      }
    } catch (e) {
      logger.w('[WinPrint] 로고 로드 실패, 계속 출력: $e');
      // 로고 로드 실패해도 출력은 계속
    }
  }

  String? _resolvePrinter() {
    final configured = PreferenceService().getWindowsPrinterName();
    if (configured != null && configured.isNotEmpty) return configured;
    return WinspoolRawClient.getDefaultPrinterName();
  }
}
