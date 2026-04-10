import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/product_provider.dart'; // [NEW] 상품 목록 연동
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/sound_service.dart';
import 'package:appfit_order_agent/utils/print/label_painter.dart';
import 'package:collection/collection.dart'; // [NEW] firstWhereOrNull 사용

import 'package:appfit_order_agent/constants/order_constants.dart';
import '../../providers/kds_unified_providers.dart';

class OutputService {
  final Ref ref;
  final Order _orderNotifier;

  OutputService(this.ref, this._orderNotifier);

  Future<void> notifyNewOrder(
    OrderModel order, {
    required bool playSound,
    bool printLabel = true, // [NEW] 라벨 출력 여부 제어
  }) async {
    try {
      final isKdsMode = ref.read(kdsModeProvider);

      // 블링크 상태 업데이트 (주문 수 변화 반영)
      _orderNotifier.updateBlinkStateExternal();

      if (isKdsMode) {
        if (playSound) {
          logger.i('[OutputService] 알람소리 재생 (KDS)');
          await ref.read(soundAppServiceProvider).playNotificationSound();
        }

        final usePrint = ref.read(preferenceServiceProvider).getUsePrint();
        if (usePrint) {
          logger.i('[OutputService] KDS 모드: 프린터 사용 설정됨, 주문서 출력 진행');
          // KDS 모드 주문서 출력 필요 시 여기에 로직 추가 가능
        } else {
          logger.i(
              '[OutputService] KDS 모드: 프린터 사용 안함 설정으로 주문서 출력 생략 (라벨은 독립적으로 동작)');
        }
      } else {
        // 일반 모드: 실제 인쇄 수행 후에만 출력 이력 기록
        final orderForPrinting = await _prepareOrderForPrinting(order);

        // 설정된 출력 개수만큼 반복 출력 (프린터 설정 고려)
        final printCount = ref.read(preferenceServiceProvider).getPrintCount();
        final useBuiltin =
            ref.read(preferenceServiceProvider).getUseBuiltinPrinter();
        final useExternal =
            ref.read(preferenceServiceProvider).getUseExternalPrinter();

        // 실제 프린터 개수 계산 (내장 + 외부)
        final actualPrinterCount = (useBuiltin ? 1 : 0) + (useExternal ? 1 : 0);
        final totalPrintCount = printCount * actualPrinterCount;

        if (totalPrintCount > 0) {
          for (int i = 0; i < printCount; i++) {
            await ref.read(printServiceProvider).printOrderReceipt(
                  order: orderForPrinting,
                  type: 'order',
                );
            logger.d(
                '[OutputService] 주문서 출력 완료: ${order.orderNo} (${i + 1}/$printCount) - 프린터: ${useBuiltin ? "내장" : ""}${useBuiltin && useExternal ? "+" : ""}${useExternal ? "외부" : ""}');
          }
        } else {
          logger.w('[OutputService] 프린터가 설정되지 않아 출력 생략: ${order.orderNo}');
        }

        if (playSound) {
          logger.i('[OutputService] 알람소리 재생 (일반 모드)');
          await ref.read(soundAppServiceProvider).playNotificationSound();
        }
      }

      // 라벨 프린트 - 수동이 아닌 자동 출력 (옵션에 따라) - 모드 무관하게 독립적으로 동작
      if (printLabel) {
        final orderForPrinting =
            await _prepareOrderForPrinting(order); // 라벨 출력을 위한 모델 보장
        await printOrderLabels(orderForPrinting);
      } else {
        logger.d('[OutputService] 라벨 출력 생략됨 (printLabel: false)');
      }

      logger.i('[OutputService] 주문 출력 처리 완료: ${order.orderNo}');
    } catch (e, s) {
      logger.e('[OutputService] 주문 출력 처리 중 오류 발생: ${order.orderNo}',
          error: e, stackTrace: s);
    }
  }

  /// 주문에 포함된 메뉴들의 라벨을 출력합니다.
  /// [isReprint] true이면 재출력 (필터링 없이 전체 출력)
  Future<void> printOrderLabels(OrderModel order, {bool isReprint = false}) async {
    try {
      final useLabel = ref.read(preferenceServiceProvider).getUseLabelPrinter();
      if (!useLabel) return;

      // 상세 정보(메뉴)가 없는 경우 로드 시도
      OrderModel orderToPrint = order;
      if (orderToPrint.menus.isEmpty) {
        logToFile(
            tag: LogTag.PLATFORM,
            message: '[OutputService] 라벨 출력 전 상세 정보 로드 시도: ${order.orderNo}');
        orderToPrint = await _prepareOrderForPrinting(order);
      }

      if (orderToPrint.menus.isEmpty) {
        logger.w('[OutputService] 라벨 출력 건너뜀: 메뉴 정보 없음 (${order.orderNo})');
        return;
      }

      logger.i('[OutputService] 라벨 출력 시작: ${orderToPrint.orderNo}');
      final printService = ref.read(printServiceProvider);
      final printDelay = ref.read(preferenceServiceProvider).getLabelPrintDelay();

      // 전체 상품 목록 로드 (완성된 모델 대기)
      final allProducts = await ref.read(productProvider.future);

      // 카테고리 필터링 (재출력이 아닌 자동 출력 시에만 적용, TPCP 매장 전용)
      // filterMode: 0=전체, 1=와플만, 2=와플제외
      final prefService = ref.read(preferenceServiceProvider);
      final filterMode = prefService.getLabelFilterMode();
      final isTpcp = prefService.isTpcpStore();
      final menusToprint = (!isReprint && filterMode != 0 && isTpcp)
          ? orderToPrint.menus.where((menu) {
              final product = allProducts.firstWhereOrNull(
                (p) =>
                    p.productId == menu.shopItemId ||
                    p.internalId == menu.shopItemId,
              );
              // TKP0051, TKP0052은 필터 모드에 상관없이 항상 출력 (product.productId 기준)
              if (product != null && OrderCategoryCodes.setItemCodes.contains(product.productId)) return true;
              final isWaffle = OrderCategoryCodes.waffleCategoryCodes
                  .contains(product?.categoryCode);
              return filterMode == 1 ? isWaffle : !isWaffle;
            }).toList()
          : orderToPrint.menus;

      if (menusToprint.isEmpty) {
        logger.d(
            '[OutputService] 라벨 출력 건너뜀: 필터 조건에 맞는 메뉴 없음 (${order.orderNo})');
        return;
      }

      // 전체 라벨 수 계산 (필터 무관, 전체 메뉴 수량 합산)
      final int totalLabels =
          orderToPrint.menus.fold(0, (sum, m) => sum + m.qty);

      // 전체 메뉴 순서 기준으로 각 메뉴의 시작 인덱스 미리 계산
      final menuStartIndex = <int, int>{};
      int runningIndex = 0;
      for (final menu in orderToPrint.menus) {
        menuStartIndex[identityHashCode(menu)] = runningIndex;
        runningIndex += menu.qty;
      }

      for (final menu in menusToprint) {
        // 서브 정보 추출 (원두, 온도, 사이즈)
        String? beanType;
        String? temperature;
        String? sizeOption;

        for (final opt in menu.options) {
          // 상품 목록에서 옵션 상품 코드로 카테고리 정보 찾기
          final product = allProducts.firstWhereOrNull(
            (p) =>
                p.productId == opt.shopOptionId ||
                p.internalId == opt.shopOptionId,
          );

          final categoryCode = product?.categoryCode;
          if (categoryCode != null &&
              OrderCategoryCodes.beanTypeCodes.contains(categoryCode)) {
            beanType = opt.optionName;
          }
          if (categoryCode != null &&
              OrderCategoryCodes.temperatureCodes.contains(categoryCode)) {
            temperature = opt.optionName;
          }
          if (categoryCode != null &&
              OrderCategoryCodes.sizeOptionCodes.contains(categoryCode)) {
            sizeOption = opt.optionName;
          }
        }

        // 서브정보로 표시된 옵션들은 하단 옵션 리스트에서 제외
        final filteredOptions = menu.options
            .where((opt) =>
                opt.optionName != beanType &&
                opt.optionName != temperature &&
                opt.optionName != sizeOption)
            .map((e) => e.optionName)
            .toList();

        // 해당 메뉴 수량만큼 반복 출력 (순번별로 이미지 생성)
        for (int i = 0; i < menu.qty; i++) {
          final labelIndex = menuStartIndex[identityHashCode(menu)]! + i + 1;
          final imageBytes = await LabelPainter.generateLabelImage(
            menuName: menu.itemName,
            options: filteredOptions,
            shopOrderNo: orderToPrint.displayNum,
            orderTime:
                DateFormat('MM/dd\nHH:mm:ss').format(orderToPrint.orderedAt),
            beanType: beanType,
            temperature: temperature,
            sizeOption: sizeOption,
            //qrData: orderToPrint.orderNo,
            memo: orderToPrint.note,
            orderIndex: labelIndex,
            orderTotal: totalLabels,
          );
          await printService.printLabel(imageBytes, orderNo: orderToPrint.displayNum, labelIndex: labelIndex, totalLabels: totalLabels);
          logger.d(
              '[OutputService] 라벨 출력(${menu.itemName}): $labelIndex/$totalLabels');
          // 연속 출력 시 프린터 버퍼 안정화를 위한 딜레이
          if (i < menu.qty - 1) {
            await Future.delayed(Duration(milliseconds: printDelay));
          }
        }
        // 다음 메뉴 출력 전 딜레이
        await Future.delayed(Duration(milliseconds: printDelay));
      }
    } catch (e, s) {
      logger.e('[OutputService] 라벨 출력 중 오류 발생: ${order.orderNo}',
          error: e, stackTrace: s);
    }
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
    // 메뉴 목록이 이미 있는 경우 현재 주문 정보 사용
    if (order.menus.isNotEmpty) {
      logger.d('[OutputService] Use existing order info: ${order.orderNo}');
      return order;
    }

    // 캐시 여부는 orderNotifier.getOrderDetail 내부에서 처리됨
    logger.d(
        '[OutputService] Fetching order detail for receipt: ${order.orderNo}');
    return _orderNotifier.getOrderDetail(order.orderNo, order.storeId);
  }
}

final outputAppServiceProvider = Provider<OutputService>((ref) {
  final orderNotifier = ref.read(orderProvider.notifier);
  return OutputService(ref, orderNotifier);
});
