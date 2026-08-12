import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_filter_strategy.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/services/label_printer/qr_payload_strategy.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/sound_service.dart';
import 'package:appfit_order_agent/core/orders/label_print_retry.dart';
import 'package:appfit_order_agent/exceptions/label_ack_timeout_exception.dart';
import 'package:appfit_order_agent/exceptions/label_print_missing_exception.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_outcome.dart';
import 'package:appfit_order_agent/exceptions/order_detail_fetch_failed_exception.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';

import 'package:appfit_core/appfit_core.dart' show MonitoringService;

class OutputService {
  final Ref ref;
  final Order _orderNotifier;

  OutputService(this.ref, this._orderNotifier);

  /// 동일 주문 내 연속 라벨 사이 최소 간격. 일부 Sunmi 프린터의 firmware 설정
  /// 'unprintable when paper not taked out'(종이 안 뗐을 때 멈춤+비프)이 걸릴
  /// idle 윈도우를 확보하기 위한 값(현장 튜닝 대상). 라벨을 촘촘히 연달아 보내면
  /// 상태 비콘이 갱신되기 전에 다음 PagePrint 가 도착해 firmware 가 연속 인쇄로
  /// 처리(비프 없이 이어져 나옴)하는 개체가 있어, 라벨 사이에 이 텀을 둔다.
  /// 주문 첫 라벨은 상위 방출 throttle(500ms)로 이미 텀이 있어 제외한다.
  static const Duration _kInterLabelDelay = Duration(milliseconds: 300);

  // ── ACK 미수신 집계용 세션 카운터 ──────────────────────────────────────────
  //
  // Sentry 이벤트만으로는 발생 "비율" 을 낼 수 없었다. 분모(총 라벨 수)가 어디에도
  // 없었고, MonitoringService.captureError 가 runtimeType 기준 5분 쿨다운을 걸어
  // 버스트는 breadcrumb 으로만 남아 사라졌다 — 즉 이벤트 개수는 하한선일 뿐이다.
  //
  // 두 누적값을 모든 이벤트에 실으면 그 두 문제가 한 번에 풀린다:
  //   • 비율 = ackTimeouts / labelsAttempted 를 이벤트 하나에서 바로 읽는다
  //   • 연속한 두 이벤트의 ackTimeouts 차이가 그 사이 실제 발생 건수 —
  //     차이가 1보다 크면 쿨다운에 먹힌 건수를 그대로 알 수 있다
  //
  // [OutputService] 는 재생성될 수 있어(order_provider.dart) 인스턴스 필드로는
  // 세션 누적이 안 된다. 앱 시작 이후 누적이므로 static.
  static int _labelsAttempted = 0;
  static int _ackTimeouts = 0;
  static final DateTime _sessionStart = DateTime.now();

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
        // 메뉴 없는 부분 데이터로 영수증을 인쇄하지 않는다. 상세조회가 실패하면
        // '내용 누락 영수증' 발행 대신 인쇄를 스킵하고 Sentry 로 보고한다.
        // 메뉴 복구는 소켓 재시도 래퍼 + refreshOrders 안전망이 담당한다.
        OrderModel? orderForPrinting;
        try {
          orderForPrinting = await _prepareOrderForPrinting(order);
        } catch (e, s) {
          logger.e('[Receipt] ${order.displayNum} 상세조회 실패 — 영수증 인쇄 스킵',
              error: e, stackTrace: s);
          MonitoringService.instance.captureError(
            OrderDetailFetchFailedException(
              orderNo: order.orderNo,
              eventType: order.orderStatus,
              source: 'receipt',
              lastError: e.toString(),
            ),
            s,
            hint: '영수증 상세조회 실패 — 부분 데이터 인쇄 차단',
            extras: {
              'orderNo': order.orderNo,
              'displayNum': order.displayNum,
            },
          );
          // 출력 누락 등록 → 메뉴 복구 시 자동 재발행. 마킹 실패가 세션 정리 중
          // 앱 크래시로 번지지 않도록 격리.
          try {
            _orderNotifier.markPendingReprint(order.orderId);
          } catch (_) {}
        }
        if (orderForPrinting != null) {
          final printCount =
              ref.read(preferenceServiceProvider).getPrintCount();
          for (int i = 0; i < printCount; i++) {
            await ref.read(printServiceProvider).printOrderReceipt(
                  order: orderForPrinting,
                  type: 'order',
                );
          }
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
        try {
          orderToPrint = await _prepareOrderForPrinting(order);
        } catch (e) {
          // 상세조회 실패로 라벨을 못 내보냄 — 출력 누락 등록 후 조용히 생략한다.
          // 상위 catch 로 던지지 않아 '라벨 출력 영역 예외'(비정상 예외용) 오탐과
          // Sentry 중복 보고를 막는다. 영수증 OFF(라벨만) 매장의 라벨 단독 누락도
          // 이 경로로 복구 큐에 등록된다.
          logger.w('[Label] ${order.displayNum} 상세조회 실패 — 라벨 생략, 복구 대기 ($e)');
          try {
            _orderNotifier.markPendingReprint(order.orderId);
          } catch (_) {}
          return;
        }
      }

      if (orderToPrint.menus.isEmpty) {
        logger.w('[Label] ${order.displayNum} 라벨 생략 (메뉴 정보 없음)');
        // 모든 라벨 경로(_NewOrderLabelTail / LabelOnlyJob / addLabelOnly)가 이
        // 깔때기로 수렴 — 라벨 단독 누락도 출력 누락으로 등록해 메뉴 복구 시 재발행.
        try {
          _orderNotifier.markPendingReprint(order.orderId);
        } catch (_) {}
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
      // QR 페이로드 포맷 토글: 0=기존(브랜드 전략), 1=신규(displayNum-cupIdx 테스트 포맷, 전역 오버라이드)
      final qrStrategy = prefService.getLabelQrPayloadFormat() == 1
          ? const DisplayNumIndexQrPayloadStrategy()
          : ref.read(qrPayloadStrategyProvider);
      // 빠른 제조 메뉴 정책 — 주문 내 라벨 정렬(mode>=1)과 마커 표시를 담당.
      // 기본값(mode=0, 지정 상품 없음)이면 정렬도 마커도 없이 종전과 동일하다.
      final fastMenuPolicy = ref.read(fastMenuPolicyProvider);
      final labels = LabelPrintData.fromOrder(
        orderToPrint,
        products: allProducts,
        filterMode: prefService.getLabelFilterMode(),
        strategy: ref.read(labelFilterStrategyProvider),
        qrStrategy: qrStrategy,
        isReprint: isReprint,
        fastMenuPolicy: fastMenuPolicy,
      );

      if (labels.isEmpty) return;

      final totalLabels = labels.first.orderTotal;

      // QR 코드 출력 토글. ON 이면 ① QR 동반 인쇄 + ② 주문번호 뒤 순번 접미사(-1, -2 ...)
      // 를 함께 적용한다. (예: 0029 → 0029-1, 0029-2). OFF 면 둘 다 미적용.
      final useQr = prefService.getLabelUseQrPrint();
      // 라벨 레이아웃은 V2(QR 우측상단)로 고정한다. (구 V1 선택 설정은 폐지됨)
      const layoutVersion = 1;

      // 누락 카운터 — 한 주문 내에서 자동 재시도(1회) 마저 실패한 라벨 추적
      int failedLabels = 0;
      final List<int> failedIndices = [];

      for (final (index, data) in labels.indexed) {
        // 동일 주문 내 연속 라벨 사이에 firmware 의 paper-not-fetched 감지가
        // 걸릴 idle 윈도우를 확보한다. index 0(주문 첫 라벨)은 상위 방출
        // throttle(500ms)로 이미 텀이 있어 제외 → 단일메뉴(1장) 주문은 추가
        // 지연 0. Windows 는 자체 PAPERNOFETCH 무한 대기가 있고 본 현상이 아직
        // 미확인이라 현재 Android 로 한정(확인되면 게이트 확대).
        if (index > 0 && Platform.isAndroid) {
          await Future.delayed(_kInterLabelDelay);
        }
        final genStart = DateTime.now();
        // 토글 ON 시 주문번호에 누적 순번(orderIndex, 1..orderTotal)을 접미사로 붙인다.
        final shopOrderNo = (useQr && data.shopOrderNo != null)
            ? '${data.shopOrderNo}-${data.orderIndex}'
            : data.shopOrderNo;
        final imageBytes = await LabelPainter.generateLabelImage(
          menuName: data.menuName,
          options: data.options,
          shopOrderNo: shopOrderNo,
          orderTime: data.orderTime,
          beanType: data.beanType,
          temperature: data.temperature,
          sizeOption: data.sizeOption,
          qrData: useQr ? data.qrData : null,
          memo: data.memo,
          orderIndex: data.orderIndex,
          orderTotal: data.orderTotal,
          layoutVersion: layoutVersion,
          // V2: QR +50% + 오류정정 L (헤더 축소로 확보한 공간 활용). V1: 종전 그대로.
          qrSize: LabelPainter.qrSizeForLayout(layoutVersion),
          qrErrorCorrectLevel:
              LabelPainter.qrErrorCorrectLevelForLayout(layoutVersion),
          // 표시는 우선순위 동작과 독립 축 — 순서만 바꾸고 인쇄물에는
          // 흔적을 남기지 않는 "조용한 운용"이 기본값(showMarker=false)이다.
          isFastMenu: data.isFastMenu && fastMenuPolicy.showMarker,
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
          reportOrderNo: orderToPrint.orderNo,
        );
        final printMs = DateTime.now().difference(printStart).inMilliseconds;
        final labelMsg =
            '[Label] $num ${data.orderIndex}/${data.orderTotal} ${data.menuName}'
            ' ${ok ? "출력끝" : "실패"} (gen=${genMs}ms, print=${printMs}ms)';
        // 정상 라벨은 콘솔로만 — 파일은 Java [LabelPrinter] 줄과 중복. 실패만 파일 기록.
        if (ok) {
          logger.d(labelMsg);
        } else {
          logToFile(tag: LogTag.WARNING, message: labelMsg);
        }
        if (!ok) {
          failedLabels++;
          failedIndices.add(data.orderIndex);
        }
      }

      if (failedLabels > 0) {
        // 운영 critical 사건 — logcat grep '누락' 으로 즉시 식별
        logToFile(
            tag: LogTag.ERROR,
            message:
                '[Label] $num 누락 $failedLabels/$totalLabels장 인덱스=$failedIndices');

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

  /// printLabel 1회 시도 → **재시도가 안전한 실패일 때만** 1.5초 delay 후 1회 재시도.
  ///
  /// Java 측에서 다음 케이스는 자체 무한 대기로 처리되어 여기로 오지 않음:
  ///   • PAPERNOFETCH (사용자가 종이 안 뗌)
  ///   • paper-out / cover-up / NoPaperCanceled (운영자 용지 교체/커버 닫음 대기)
  ///
  /// [LabelPrintOutcome.retryable] 만 재시도한다. 해당 케이스:
  ///   • USB 포트 단절 / 좀비 (다음 시도 시 재연결 자동 회복)
  ///   • 펌웨어 일시 ERROR (engine/voltage/cutter 등) — 0.5초 짧은 게이트 통과 후 회복 기대
  ///   • PagePrint 도중 NoPaper race — 다음 시도 시 진입 게이트가 무한 대기로 흡수
  ///
  /// [LabelPrintOutcome.submittedNoAck] 은 **재시도하지 않는다.** PagePrint 가 이미
  /// 펌웨어로 나간 뒤라 재발사하면 같은 라벨이 2장 인쇄된다 — 2026-08-03 아오야마점
  /// #0906/#0956 사고의 정확한 경로다. ACK timeout 은 "종이가 안 나왔다"가 아니라
  /// "응답을 못 받았다"일 뿐이므로 성공으로 취급하고 Sentry 로 빈도만 집계한다.
  Future<bool> _printLabelWithRetry({
    required PrintService printService,
    required Uint8List imageBytes,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
    required String reportOrderNo,
  }) async {
    // 분모. 재시도 여부와 무관하게 "라벨 1장 = 1" 로 센다.
    _labelsAttempted++;
    return runLabelPrintWithRetry(
      dispatch: () => _dispatchPrintLabel(
        printService: printService,
        imageBytes: imageBytes,
        orderNo: orderNo,
        labelIndex: labelIndex,
        totalLabels: totalLabels,
      ),
      onAckTimeout: (attempt) => _reportAckTimeout(
        printService: printService,
        displayNum: orderNo,
        reportOrderNo: reportOrderNo,
        labelIndex: labelIndex,
        totalLabels: totalLabels,
        attempt: attempt,
      ),
      logPrefix: '[Label] $orderNo $labelIndex/$totalLabels',
    );
  }

  /// ACK 미수신을 기록한다. 재발행하지 않으므로 운영자 조치는 없고, 발생 빈도를
  /// 매장·기기별로 추적하는 것이 목적이다.
  ///
  /// 네이티브 진단 스냅샷을 함께 싣는다. 이게 없으면 이벤트가 "몇 번 났다" 만 알려주고
  /// **왜 났는지는 답하지 못한다** — 판정 근거는 기기 로그 파일에만 남아 있었다.
  /// 특히 비콘 age 가 핵심 판별자다: timeout 순간 비콘이 살아 있었으면 유실된 것은
  /// print-result 응답 하나뿐이고, 비콘도 함께 끊겼으면 IN 엔드포인트 전체가 멎은 것이다.
  Future<void> _reportAckTimeout({
    required PrintService printService,
    required String displayNum,
    required String reportOrderNo,
    required int labelIndex,
    required int totalLabels,
    required int attempt,
  }) async {
    _ackTimeouts++;
    // 파일 로그는 남기지 않는다 — 바로 앞줄에 Java 가 찍는
    // `실패 [완료신호 없음 …] 프린터=… 라벨=… 연결=… | …` 이 같은 사건을 더 자세히
    // 기록한다. 재시도 회차는 Java 의 `출력시작` 반복 횟수로 그대로 드러난다.
    logger.w('[Label] $displayNum $labelIndex/$totalLabels'
        ' ACK 미수신 ($attempt차) — 인쇄된 것으로 간주, 재시도 안 함');
    // 조회 실패는 null 로 흡수된다 — 진단이 없어도 집계는 진행한다.
    final diagnostic = await printService.fetchLastLabelAckDiagnostic();
    MonitoringService.instance.captureError(
      LabelAckTimeoutException(
        orderNo: reportOrderNo,
        displayNum: displayNum,
        labelIndex: labelIndex,
        totalLabels: totalLabels,
        attempt: attempt,
      ),
      StackTrace.current,
      hint: '라벨 ACK 미수신 — 중복 방지를 위해 재시도 생략 (누락 아님)',
      extras: {
        'orderNo': reportOrderNo,
        'displayNum': displayNum,
        'labelIndex': labelIndex,
        'totalLabels': totalLabels,
        'attempt': attempt,
        'diagnostic': diagnostic ?? '(없음)',
        // 분모·누적. 비율 산출 + 쿨다운에 먹힌 건수 복원용 (필드 선언부 주석 참조).
        'labelsAttempted': _labelsAttempted,
        'ackTimeouts': _ackTimeouts,
        'sessionMinutes': DateTime.now().difference(_sessionStart).inMinutes,
      },
    );
  }

  /// SDK 호출 1지점. 플랫폼 분기는 [PrintService.printLabel] 내부에서 처리:
  /// - Windows: autoreplyprint.dll FFI (CP_Label_DrawImageFromData, PNG bytes)
  /// - Android: MethodChannel (Caysn AutoReplyPrint Java SDK, PNG bytes)
  ///
  /// 양 플랫폼 모두 PNG bytes 입력. 분류/필터/Painter/retry 흐름은 위층에서
  /// 동일하게 처리하므로 양 플랫폼 라벨 출력 결과는 동등하다.
  Future<LabelPrintOutcome> _dispatchPrintLabel({
    required PrintService printService,
    required Uint8List imageBytes,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    return printService.printLabelDetailed(
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
