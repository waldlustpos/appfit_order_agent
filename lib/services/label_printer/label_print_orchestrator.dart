// 주문 1건 -> 라벨 다발 출력 오케스트레이터.
//
// LabelPrintData.fromOrder 로 메뉴별 ordrCnt 만큼 라벨을 펼친 뒤
// LabelPainter.generateLabelImage 로 PNG bytes 를 만들어 backend 로 전달.
// 실패 시 1.5초 후 1회 재시도 (appfit 패턴).
//
// 주의:
// - dedup 은 OutputQueueService 의 3-set in-flight 락이 담당하므로 여기서는
//   별도 dedup 을 하지 않는다. (kokonut 의 _inFlightOrderIds static Set 미도입)
// - Backend abstract 도입 후에는 양 플랫폼 공통 진입점이 된다. 현재는 Windows
//   만 backend 가 있고 Android 는 OutputService 의 기존 경로를 그대로 사용.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:appfit_order_agent/exceptions/label_print_missing_exception.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/print/label_painter.dart';

import 'label_print_data.dart';
import 'label_printer_options.dart';
import 'windows/windows_label_printer_backend.dart';

class LabelPrintOrchestrator {
  LabelPrintOrchestrator({WindowsLabelPrinterBackend? service})
      : _service = service ?? WindowsLabelPrinterBackend.instance;

  final WindowsLabelPrinterBackend _service;
  static const Duration _retryDelay = Duration(milliseconds: 1500);

  /// 사용자가 라벨 프린터 사용을 켜놓았고 Windows 인 경우에만 출력.
  /// 영수증 출력 흐름을 차단하지 않도록 호출자는 `unawaited` 로 띄우는 것을 권장.
  Future<void> printOrderLabels(OrderModel order) async {
    if (!_service.isAvailable || !Platform.isWindows) return;
    final pref = PreferenceService();
    if (!pref.getUseLabelPrinter()) return;

    final labels = LabelPrintData.fromOrder(order);
    if (labels.isEmpty) return;

    final orderTag =
        order.displayNum.isNotEmpty ? order.displayNum : order.orderNo;

    final options = _readOptions(pref);
    final failedIndices = <int>[];
    for (final data in labels) {
      final ok = await _printOneWithRetry(data, options, orderTag);
      if (!ok) failedIndices.add(data.orderIndex);
    }

    if (failedIndices.isNotEmpty) {
      logger.e(
          '[Label] $orderTag 누락 ${failedIndices.length}/${labels.length}장 idx=$failedIndices');
      _reportLabelMissing(order, orderTag, labels.length, failedIndices);
    }
  }

  /// 설정 화면의 "테스트 인쇄" 버튼용 - 더미 라벨 1장 출력.
  Future<bool> printTestLabel() async {
    if (!_service.isAvailable || !Platform.isWindows) return false;
    final pref = PreferenceService();
    final data = LabelPrintData.testSample();
    final options = _readOptions(pref);
    return _printOneWithRetry(data, options, 'TEST');
  }

  Future<bool> _printOneWithRetry(
    LabelPrintData data,
    LabelPrinterOptions options,
    String orderTag,
  ) async {
    final Uint8List png;
    try {
      png = await LabelPainter.generateLabelImage(
        menuName: data.menuName,
        options: data.options,
        shopOrderNo: data.shopOrderNo,
        orderTime: data.orderTime,
        beanType: data.beanType,
        temperature: data.temperature,
        sizeOption: data.sizeOption,
        qrData: data.qrData,
        memo: data.memo,
        orderIndex: data.orderIndex,
        orderTotal: data.orderTotal,
        showDetailQr: data.showDetailQr,
      );
    } catch (e, s) {
      logger.e('[Label][$orderTag] painter 예외', error: e, stackTrace: s);
      return false;
    }

    final ok1 = await _service.printPng(
      pngBytes: png,
      width: LabelPainter.width.toInt(),
      height: LabelPainter.height.toInt(),
      options: options,
      orderNo: orderTag,
      labelIndex: data.orderIndex,
      totalLabels: data.orderTotal,
    );
    if (ok1) return true;

    await Future.delayed(_retryDelay);

    return _service.printPng(
      pngBytes: png,
      width: LabelPainter.width.toInt(),
      height: LabelPainter.height.toInt(),
      options: options,
      orderNo: orderTag,
      labelIndex: data.orderIndex,
      totalLabels: data.orderTotal,
    );
  }

  LabelPrinterOptions _readOptions(PreferenceService pref) {
    return LabelPrinterOptions(
      autoReplyMode: pref.getLabelAutoReplyMode(),
      useFeedToTear: pref.getLabelUseFeedToTear(),
      useBackToPrint: pref.getLabelUseBackToPrint(),
      useCalibrate: pref.getLabelUseCalibrate(),
    );
  }

  /// 라벨 누락 발생 시 Sentry 로 보고.
  void _reportLabelMissing(
    OrderModel order,
    String displayTag,
    int totalLabels,
    List<int> failedIndices,
  ) {
    try {
      final exception = LabelPrintMissingException(
        orderNo: order.orderId,
        displayNum: displayTag,
        failedCount: failedIndices.length,
        totalLabels: totalLabels,
        failedIndices: List<int>.unmodifiable(failedIndices),
      );
      Sentry.captureException(
        exception,
        hint: Hint.withMap({
          'hint': '라벨 누락 - 운영자 [라벨 재출력] 으로 복구 가능',
        }),
      );
    } catch (e, s) {
      logger.w('[Label] Sentry 보고 실패', error: e, stackTrace: s);
    }
  }
}
