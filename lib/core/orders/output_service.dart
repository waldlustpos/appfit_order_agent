import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/sound_service.dart';
import 'package:appfit_order_agent/exceptions/label_print_missing_exception.dart';
import 'package:appfit_order_agent/utils/print/label_painter.dart';

import 'package:appfit_core/appfit_core.dart' show MonitoringService;
import '../../providers/kds_unified_providers.dart';

class OutputService {
  final Ref ref;
  final Order _orderNotifier;

  OutputService(this.ref, this._orderNotifier);

  Future<void> notifyNewOrder(
    OrderModel order, {
    required bool playSound,
    bool printLabel = true, // [NEW] 라벨 출력 여부 제어
    bool forceOrderReceipt = false,
  }) async {
    try {
      final isKdsMode = ref.read(kdsModeProvider);
      // KDS 모드라도 자동접수 ON 일 때는 일반 모드와 동일하게 주문서를 출력해야 한다
      // (commit 36cfad8 자동접수 파이프라인 확장의 마지막 누락 분기 보강).
      // forceOrderReceipt: 외부 디바이스가 접수한 PREPARING 이벤트가 KDS 에 도달했을 때
      // 자동접수 OFF 라도 주문서를 인쇄해야 하는 케이스용.
      final isKdsAcceptOrders = ref.read(orderProvider).isKdsAcceptOrders;
      final shouldPrintOrderReceipt =
          !isKdsMode || isKdsAcceptOrders || forceOrderReceipt;

      // 블링크 상태 업데이트 (주문 수 변화 반영)
      _orderNotifier.updateBlinkStateExternal();

      if (shouldPrintOrderReceipt) {
        final orderForPrinting = await _prepareOrderForPrinting(order);
        final printCount = ref.read(preferenceServiceProvider).getPrintCount();
        for (int i = 0; i < printCount; i++) {
          await ref.read(printServiceProvider).printOrderReceipt(
                order: orderForPrinting,
                type: 'order',
              );
        }
      }

      if (playSound) {
        await ref.read(soundAppServiceProvider).playNotificationSound();
      }

      // 라벨 프린트 - 수동이 아닌 자동 출력 (옵션에 따라) - 모드 무관하게 독립적으로 동작
      if (printLabel) {
        final orderForPrinting = await _prepareOrderForPrinting(order);
        await printOrderLabels(orderForPrinting);
      }
    } catch (e, s) {
      logger.e('[Label] ${order.displayNum} 주문 출력 처리 오류',
          error: e, stackTrace: s);
      logToFile(
          tag: LogTag.ERROR,
          message: '[Label] ${order.displayNum} 주문 출력 처리 오류: $e');
    }
  }

  /// 주문에 포함된 메뉴들의 라벨을 출력합니다.
  /// [isReprint] true이면 재출력 (필터링 없이 전체 출력)
  Future<void> printOrderLabels(OrderModel order,
      {bool isReprint = false}) async {
    try {
      final useLabel = ref.read(preferenceServiceProvider).getUseLabelPrinter();
      if (!useLabel) return;

      // 상세 정보(메뉴)가 없는 경우 로드 시도
      OrderModel orderToPrint = order;
      if (orderToPrint.menus.isEmpty) {
        logToFile(
            tag: LogTag.PLATFORM,
            message: '[Label] ${order.displayNum} 메뉴 정보 미보유 — 상세 조회 시도');
        orderToPrint = await _prepareOrderForPrinting(order);
      }

      if (orderToPrint.menus.isEmpty) {
        logger.w('[Label] ${order.displayNum} 라벨 생략 (메뉴 정보 없음)');
        return;
      }

      // 진입 로그: 운영자 단위 식별 — displayNum + 메뉴/총라벨수 + reprint 플래그.
      final int entryTotalLabels =
          orderToPrint.menus.fold(0, (sum, m) => sum + m.qty);
      final num = orderToPrint.displayNum;
      final entryMsg = '[Label] $num 인쇄진입'
          ' (menus=${orderToPrint.menus.length}, labels=$entryTotalLabels'
          '${isReprint ? ', 재출력' : ''})';
      logToFile(tag: LogTag.PLATFORM, message: entryMsg);
      final printService = ref.read(printServiceProvider);

      // 라벨 묶음 생성 — 카테고리 필터링, 옵션 분류, QR JSON 페이로드,
      // 메뉴별 라벨 번호 계산을 모두 LabelPrintData.fromOrder() 가 처리.
      final allProducts = await ref.read(productProvider.future);
      final prefService = ref.read(preferenceServiceProvider);
      final labels = LabelPrintData.fromOrder(
        orderToPrint,
        products: allProducts,
        filterMode: prefService.getLabelFilterMode(),
        isTpcpStore: prefService.isTpcpStore(),
        isReprint: isReprint,
      );

      if (labels.isEmpty) return;

      final totalLabels = labels.first.orderTotal;

      // 누락 카운터 — 한 주문 내에서 자동 재시도(1회) 마저 실패한 라벨 추적
      int failedLabels = 0;
      final List<int> failedIndices = [];

      for (final data in labels) {
        final genStart = DateTime.now();
        final imageBytes = await LabelPainter.generateLabelImage(
          menuName: data.menuName,
          options: data.options,
          shopOrderNo: data.shopOrderNo,
          orderTime: data.orderTime,
          beanType: data.beanType,
          temperature: data.temperature,
          sizeOption: data.sizeOption,
          qrData: prefService.getLabelUseQrPrint() ? data.qrData : null,
          memo: data.memo,
          orderIndex: data.orderIndex,
          orderTotal: data.orderTotal,
        );
        final genMs = DateTime.now().difference(genStart).inMilliseconds;

        // samplelabel 표준 흐름: CP_Pos_QueryPrintResult 가 인쇄 완료까지 동기 블로킹.
        // Java 측이 PAPERNOFETCH 무한 대기로 사용자 떼기까지 누락 0 보장 — 여기서는
        // ERROR/포트오류/연결끊김 같은 다른 종류 실패만 1회 자동 재시도.
        final printStart = DateTime.now();
        final ok = await _printLabelWithRetry(
          printService: printService,
          imageBytes: imageBytes,
          orderNo: orderToPrint.displayNum,
          labelIndex: data.orderIndex,
          totalLabels: data.orderTotal,
        );
        final printMs = DateTime.now().difference(printStart).inMilliseconds;
        logToFile(
            tag: ok ? LogTag.PLATFORM : LogTag.WARNING,
            message:
                '[Label] $num ${data.orderIndex}/${data.orderTotal} ${data.menuName}'
                ' ${ok ? "출력끝" : "실패"} (gen=${genMs}ms, print=${printMs}ms)');
        if (!ok) {
          failedLabels++;
          failedIndices.add(data.orderIndex);
        }
      }

      if (failedLabels > 0) {
        // 운영 critical 사건 — logcat grep '★' 으로 즉시 식별
        logToFile(
            tag: LogTag.ERROR,
            message:
                '[Label] $num ★ 누락 $failedLabels/$totalLabels장 인덱스=$failedIndices');

        // Sentry 전송 — 동일 매장 5분 쿨다운(MonitoringService 내장)
        MonitoringService.instance.captureError(
          LabelPrintMissingException(
            orderNo: orderToPrint.orderNo,
            displayNum: orderToPrint.displayNum,
            failedCount: failedLabels,
            totalLabels: totalLabels,
            failedIndices: failedIndices,
          ),
          StackTrace.current,
          hint: '라벨 누락 — 운영자 [라벨 재출력] 으로 복구 가능',
          extras: {
            'orderNo': orderToPrint.orderNo,
            'displayNum': orderToPrint.displayNum,
            'failedCount': failedLabels,
            'totalLabels': totalLabels,
            'failedIndices': failedIndices.join(','),
            'isReprint': isReprint,
          },
        );
      }
    } catch (e, s) {
      logger.e('[Label] ${order.displayNum} 라벨 출력 영역 예외',
          error: e, stackTrace: s);
      logToFile(
          tag: LogTag.ERROR,
          message: '[Label] ${order.displayNum} 라벨 출력 영역 예외: $e');
      // 라벨 출력 영역의 비정상 예외 (메뉴 로드/필터 등) — Sentry 전송
      MonitoringService.instance.captureError(
        e,
        s,
        hint: '[OutputService.printOrderLabels] 라벨 출력 영역 예외',
        extras: {
          'orderNo': order.orderNo,
          'displayNum': order.displayNum,
        },
      );
    }
  }

  /// printLabel 1회 시도 → 실패 시 1.5초 delay 후 1회 재시도. 총 최대 2회.
  ///
  /// Java 측에서 다음 케이스는 자체 무한 대기로 처리되어 여기로 false 가 오지 않음:
  ///   • PAPERNOFETCH (사용자가 종이 안 뗌)
  ///   • paper-out / cover-up / NoPaperCanceled (운영자 용지 교체/커버 닫음 대기)
  ///
  /// 따라서 이 헬퍼의 1.5초 재시도는 다음 케이스의 안전망:
  ///   • USB 포트 단절 / 좀비 (다음 시도 시 재연결 자동 회복)
  ///   • 펌웨어 일시 ERROR (engine/voltage/cutter 등) — 0.5초 짧은 게이트 통과 후 회복 기대
  ///   • PagePrint 도중 NoPaper race — 다음 시도 시 진입 게이트가 무한 대기로 흡수
  Future<bool> _printLabelWithRetry({
    required PrintService printService,
    required Uint8List imageBytes,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    Future<bool> dispatch() => _dispatchPrintLabel(
          printService: printService,
          imageBytes: imageBytes,
          orderNo: orderNo,
          labelIndex: labelIndex,
          totalLabels: totalLabels,
        );

    final ok1 = await dispatch();
    if (ok1) return true;

    logToFile(
        tag: LogTag.WARNING,
        message: '[Label] $orderNo $labelIndex/$totalLabels'
            ' 1차실패 (paper/cover 외 일시적) → 1.5초 후 재시도');
    await Future.delayed(const Duration(milliseconds: 1500));

    final ok2 = await dispatch();
    if (!ok2) {
      logToFile(
          tag: LogTag.ERROR,
          message: '[Label] $orderNo $labelIndex/$totalLabels 재시도실패 — 누락');
    }
    return ok2;
  }

  /// SDK 호출 1지점. 플랫폼 분기는 [PrintService.printLabel] 내부에서 처리:
  /// - Windows: autoreplyprint.dll FFI (CP_Label_DrawImageFromData, PNG bytes)
  /// - Android: MethodChannel (Caysn AutoReplyPrint Java SDK, PNG bytes)
  ///
  /// 양 플랫폼 모두 PNG bytes 입력. 분류/필터/Painter/retry 흐름은 위층에서
  /// 동일하게 처리하므로 양 플랫폼 라벨 출력 결과는 동등하다.
  Future<bool> _dispatchPrintLabel({
    required PrintService printService,
    required Uint8List imageBytes,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    return printService.printLabel(
      imageBytes,
      orderNo: orderNo,
      labelIndex: labelIndex,
      totalLabels: totalLabels,
    );
  }

  Future<void> printCancelReceiptById({
    required String orderId,
    required String storeId,
  }) async {
    try {
      final isKdsMode = ref.read(kdsModeProvider);
      if (isKdsMode) {
        final usePrint = ref.read(preferenceServiceProvider).getUsePrint();
        if (!usePrint) {
          logger.i('[OutputService] KDS 모드: 취소 영수증 출력 생략 (상점 설정 꺼짐)');
          return;
        }
      }

      // 상세 정보 확보 (상태/캐시/원격 순으로)
      OrderModel? base = _orderNotifier.getCachedOrderDetail(orderId);
      base ??= await _orderNotifier.getOrderDetail(orderId, storeId);

      // 취소 상태로 보정하여 출력
      final orderForCancel = base.copyWith(
        status: OrderStatus.CANCELLED,
        orderStatus: '9001',
        updateTime: DateTime.now(),
      );

      // 출력 설정 확인은 print_service 내부에서 처리됨
      await ref.read(printServiceProvider).printOrderReceipt(
            order: orderForCancel,
            type: 'order',
            isCancelReceipt: true,
          );
      logger.i('[OutputService] 취소 영수증 출력 완료: $orderId');
    } catch (e, s) {
      logger.e('[OutputService] 취소 영수증 출력 실패: $orderId',
          error: e, stackTrace: s);
    }
  }

  Future<OrderModel> _prepareOrderForPrinting(OrderModel order) async {
    if (order.menus.isNotEmpty) return order;
    return _orderNotifier.getOrderDetail(order.orderNo, order.storeId);
  }
}

final outputAppServiceProvider = Provider<OutputService>((ref) {
  final orderNotifier = ref.read(orderProvider.notifier);
  return OutputService(ref, orderNotifier);
});

/// 라벨 누락 발생을 Sentry 에 분류 가능하도록 표시하는 마커 예외.
///
/// throw 되지 않고 [MonitoringService.captureError] 의 첫 번째 인자로만 사용됨.
/// 전용 타입을 두는 이유: `captureError` 는 `exception.runtimeType` 으로
/// 5분 쿨다운 키를 만들므로 ([monitoring_service.dart:188]),
/// 일반 [Exception] 으로 보내면 다른 종류 예외와 키 충돌이 발생.
/// 라벨 누락 사건만 별도 카운트되도록 전용 클래스로 분리.
// LabelPrintMissingException 은 lib/exceptions/label_print_missing_exception.dart
// 로 추출되었다. 호출자는 export 또는 직접 import 사용.
