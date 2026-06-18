import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/common/action_button_shell.dart';
import 'package:appfit_order_agent/widgets/common/async_action_button.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/widgets/common/print_action_button.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/currency_provider.dart';
import 'package:appfit_order_agent/services/output_queue_service.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/widgets/order/order_menu_list_widget.dart';
import 'package:appfit_order_agent/widgets/order/order_payment_info_widget.dart';
import 'package:appfit_order_agent/widgets/order/order_info_panel_widget.dart';

class OrderDetailPopup extends ConsumerStatefulWidget {
  final OrderModel order;
  final bool isFromHistory;
  final bool isFromKds;
  final bool isFromCompletedOrCancelled;
  final bool isFromAllTab;

  const OrderDetailPopup({
    Key? key,
    required this.order,
    this.isFromHistory = false,
    this.isFromKds = false,
    this.isFromCompletedOrCancelled = false,
    this.isFromAllTab = false,
  }) : super(key: key);

  @override
  ConsumerState<OrderDetailPopup> createState() => _OrderDetailPopupState();
}

class _OrderDetailPopupState extends ConsumerState<OrderDetailPopup> {
  late ScrollController _menuScrollController;

  late final OrderModel _originalOrder;

  @override
  void initState() {
    super.initState();
    _menuScrollController = ScrollController();
    _originalOrder = widget.order;
    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            '주문 상세 팝업창 열기: orderId=${_originalOrder.orderNo}, simpleNum=${_originalOrder.shopOrderNo}, displayNum=${_originalOrder.displayNum}');
    Future.microtask(() {
      final orderDetailNotifier = ref.read(orderDetailProvider.notifier);
      orderDetailNotifier.setOrder(widget.order);
      _updateOrderFromList();
      _fetchOrderDetailIfNeeded();
    });
  }

  @override
  void dispose() {
    _menuScrollController.dispose();
    super.dispose();
  }

  void _updateOrderFromList() {
    final orderState = ref.read(orderProvider);
    final orderDetailNotifier = ref.read(orderDetailProvider.notifier);
    final currentOrder = ref.read(orderDetailProvider).order;
    if (currentOrder == null) return;

    final currentOrderInList = orderState.orders.firstWhere(
      (o) => o.orderNo == currentOrder.orderNo,
      orElse: () => currentOrder,
    );

    if (currentOrderInList.orderNo == currentOrder.orderNo &&
        currentOrderInList.status != currentOrder.status) {
      orderDetailNotifier.setOrder(currentOrder.copyWith(
        status: currentOrderInList.status,
        orderStatus: currentOrderInList.orderStatus,
      ));
    }
  }

  Future<void> _fetchOrderDetailIfNeeded() async {
    final orderDetailNotifier = ref.read(orderDetailProvider.notifier);
    final currentOrder = ref.read(orderDetailProvider).order;
    if (currentOrder == null) return;

    if (currentOrder.isDetailLoaded) {
      logger.d('상세 정보가 이미 로드되어 있습니다: ${currentOrder.menus.length}개 메뉴');
      return;
    }

    logger.i('주문 상세 정보(메뉴 목록)를 가져옵니다.');
    if (!mounted) return;

    await orderDetailNotifier.fetchOrderDetail(
      currentOrder.orderNo,
      currentOrder.storeId,
    );
  }

  Future<bool> _updateOrderStatus(OrderStatus newStatus,
      {String? readyTime}) async {
    final currentOrder = ref.read(orderDetailProvider).order;
    if (currentOrder == null) return false;

    try {
      bool success = false;
      final orderNotifier = ref.read(orderProvider.notifier);

      if (newStatus == OrderStatus.CANCELLED) {
        if (widget.isFromHistory) {
          logger.d(
              '주문 내역 화면에서 취소 요청 - OrderHistoryProvider 사용: ${currentOrder.orderNo}');
          final orderHistoryNotifier = ref.read(orderHistoryProvider.notifier);
          success =
              await orderHistoryNotifier.cancelOrder(currentOrder.orderNo);
        } else {
          success = await orderNotifier.cancelOrder(currentOrder.orderNo);
          logger.d(
              '현재 주문 화면에서 취소 요청 - OrderProvider 사용: ${currentOrder.orderNo}');
        }
      } else {
        success = await orderNotifier.updateOrderStatus(currentOrder, newStatus,
            readyTime: readyTime);
      }

      if (success) {
        if (!widget.isFromHistory) {
          final updatedOrder = currentOrder.copyWith(
            status: newStatus,
            orderStatus: _getStatusCode(newStatus),
            updateTime: DateTime.now(),
          );

          if (newStatus == OrderStatus.PREPARING) {
            orderNotifier.processOrderOutput(updatedOrder, playSound: false);
          }

          Future.delayed(Duration.zero, () {
            orderNotifier.updateOrderInList(updatedOrder);
          });
        }
      }

      return success;
    } catch (e, s) {
      logger.e('주문 상태 업데이트 API 호출 오류', error: e, stackTrace: s);
      return false;
    }
  }

  String _getStatusCode(OrderStatus status) {
    switch (status) {
      case OrderStatus.NEW:
        return "2003";
      case OrderStatus.PREPARING:
        return "2007";
      case OrderStatus.READY:
        return "2009";
      case OrderStatus.DONE:
        return "2020";
      case OrderStatus.CANCELLED:
        return "9001";
    }
  }

  Future<void> _handleStatusUpdate(
      Future<bool> Function() updateFunction, String actionId) async {
    String? errorMessage;
    final currentOrder = ref.read(orderDetailProvider).order;
    final orderInfo = currentOrder != null
        ? 'displayNum=${currentOrder.displayNum}, simpleNum=${currentOrder.shopOrderNo}, orderId=${currentOrder.orderId}'
        : 'order=null';
    try {
      final success = await updateFunction();
      if (success) {
        logToFile(
            tag: LogTag.UI_ACTION,
            message: '상태 변경 성공: action=$actionId, $orderInfo');
        if (mounted) {
          Navigator.of(context).pop();
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } else {
        logToFile(
            tag: LogTag.UI_ACTION,
            message: '상태 변경 실패: action=$actionId, $orderInfo');
        errorMessage = t.order_detail.status_update_fail;
      }
    } catch (e, s) {
      logToFile(
          tag: LogTag.UI_ACTION,
          message: '상태 변경 오류: action=$actionId, $orderInfo, error=$e');
      errorMessage = e is ApiException ? e.message : '오류 발생: $e';
      logger.e('상태 업데이트 처리 중 오류', error: e, stackTrace: s);
    } finally {
      if (mounted && errorMessage != null) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error_title,
          content: errorMessage,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderDetailState = ref.watch(orderDetailProvider);
    final String currencyUnit = ref.watch(currencySymbolProvider);
    final order = orderDetailState.order?.copyWith(
      status: _originalOrder.status,
      orderStatus: _originalOrder.orderStatus,
    );

    if (order == null) {
      return const Dialog(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Dialog(
      backgroundColor: AppStyles.gray1,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bLg,
      ),
      insetPadding: const EdgeInsets.all(AppSpacing.s16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 650),
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: orderDetailState.isLoading
            ? _buildLoadingState()
            : orderDetailState.errorMessage != null
                ? _buildErrorState(orderDetailState.errorMessage!)
                : _buildContent(order, currencyUnit),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.s16),
          Text(t.order_detail.loading),
        ],
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppStyles.kRed),
          const SizedBox(height: AppSpacing.s16),
          Text(
            t.order_detail.error_prefix(error: errorMessage),
            textAlign: TextAlign.center,
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.s24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(t.common.refresh),
            onPressed: _fetchOrderDetailIfNeeded,
            style: AppStyles.primaryButton(),
          ),
          const SizedBox(height: AppSpacing.s8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.close),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(OrderModel order, String currencyUnit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(order),
        const SizedBox(height: AppSpacing.s16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: OrderMenuListWidget(
                  menus: order.orderMenuList,
                  scrollController: _menuScrollController,
                  currencySymbol: currencyUnit,
                  orderCount: int.tryParse(order.orderCount) ?? 0,
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              Expanded(
                child: OrderPaymentInfoWidget(
                  totalAmount: order.totalAmount,
                  discountAmount: order.discountAmount,
                  paymentAmount: order.paymentAmount,
                  currencySymbol: currencyUnit,
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              SizedBox(
                width: 260,
                child: OrderInfoPanelWidget(order: order),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        _buildFooter(order),
      ],
    );
  }

  Widget _buildHeader(OrderModel order) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: AppSpacing.s12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              order.displayNum,
              style: AppTextStyles.display,
            ),
            if (ref.read(preferenceServiceProvider).getShowOrderTypeBadge())
              _OrderTypePill(orderType: order.orderType),
            _StatusPill(order: order),
            _SourcePill(source: order.source),
            Text(
              DateFormat('yyyy-MM-dd HH:mm:ss').format(order.orderedAt),
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 24),
          splashRadius: AppSpacing.s20,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildFooter(OrderModel order) {
    final actions = _buildActionButtons(order);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (actions.secondary.isNotEmpty)
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: actions.secondary,
            )
          else
            const SizedBox.shrink(),
          actions.primary,
        ],
      ),
    );
  }

  ({List<Widget> secondary, Widget primary}) _buildActionButtons(
      OrderModel order) {
    final prefs = ref.read(preferenceServiceProvider);
    final isKdsMode = prefs.getKdsMode();
    final showReceiptReprint =
        prefs.getUseBuiltinPrinter() || prefs.getUseExternalPrinter();
    final showLabelReprint = prefs.getUseLabelPrinter();

    Widget closeButton({bool isMainAction = false}) => AsyncActionButton(
          text: t.common.close,
          isMainAction: isMainAction,
          onPressed: () async => Navigator.of(context).pop(),
        );

    // 라벨 재출력 — PrintActionButton 으로 통일 (위젯 내부 1초 debounce + 자기 버튼만 인디케이터)
    Widget labelReprintBtn() => PrintActionButton(
          text: t.order_detail.btn_label_reprint,
          onPressed: () {
            logToFile(
                tag: LogTag.UI_ACTION,
                message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
            ref.read(outputQueueServiceProvider).addReprint(order);
          },
        );

    // 영수증 재출력 — PrintActionButton (영수증 + 라벨 동시 큐 직렬 처리)
    Widget receiptReprintBtn() => PrintActionButton(
          text: t.order_detail.btn_receipt_reprint,
          onPressed: () {
            logToFile(
                tag: LogTag.UI_ACTION,
                message:
                    '영수증 재출력 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
            ref.read(outputQueueServiceProvider).addReceiptReprint(order);
          },
        );

    // 어떤 화면에서도 설정 플래그(영수증=내장|외부, 라벨)로만 가시성 결정.
    List<Widget> reprintButtons() => [
          if (showReceiptReprint) receiptReprintBtn(),
          if (showLabelReprint) labelReprintBtn(),
        ];

    // 완료/취소 탭: 닫기 + 재출력
    if (widget.isFromCompletedOrCancelled) {
      return (
        secondary: reprintButtons(),
        primary: closeButton(isMainAction: true),
      );
    }

    // KDS 모드(=sub-display) 전체 탭 진입 정책.
    // - 자동접수 OFF: 기존처럼 조회 전용 (닫기 + 재출력)
    // - 자동접수 ON: 아래 isFromHistory 분기(L645)로 떨어뜨려 메인 모드 "주문내역" 탭과
    //   동일하게 주문 취소가 가능하도록 한다.
    if (widget.isFromKds && isKdsMode && widget.isFromAllTab) {
      final isKdsAcceptOrders = prefs.getKdsAcceptOrders();
      if (!isKdsAcceptOrders) {
        return (
          secondary: reprintButtons(),
          primary: closeButton(isMainAction: true),
        );
      }
      // 자동접수 ON 케이스는 fall-through → isFromHistory 분기에서 cancel/close 처리.
    }

    // 준비 시간 선택 다이얼로그 — await 패턴으로 변환하여
    // AsyncActionButton 의 busy 가 status update 끝까지 유지되도록 한다.
    Future<void> acceptOrder() async {
      if (!mounted) return;
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '주문 접수 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      final time = await showDialog<String>(
        context: context,
        builder: (BuildContext timeContext) {
          return AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.bLg,
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t.order_detail.time_select_title,
                  style: AppTextStyles.title,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 24),
                  splashRadius: AppSpacing.s20,
                  onPressed: () => Navigator.of(timeContext).pop(),
                ),
              ],
            ),
            titlePadding: const EdgeInsets.fromLTRB(
              AppSpacing.s24,
              AppSpacing.s24,
              AppSpacing.s24,
              0,
            ),
            content: Text(
              t.order_detail.time_select_content,
              style: AppTextStyles.body,
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              AppSpacing.s24,
              AppSpacing.s16,
              AppSpacing.s24,
              0,
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s24,
              vertical: AppSpacing.s24,
            ),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['5', '10', '15']
                    .map((m) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s8),
                          child: ElevatedButton(
                            style: AppStyles.primaryButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s24,
                                vertical: AppSpacing.s12,
                              ),
                              minimumSize: const Size(88, 44),
                            ).copyWith(
                              textStyle: WidgetStatePropertyAll(
                                AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            onPressed: () {
                              logToFile(
                                  tag: LogTag.UI_ACTION,
                                  message: '주문 접수 버튼 -> 시간선택 $m분');
                              Navigator.of(timeContext).pop(m);
                            },
                            child: Text(t.order_detail.minutes(n: m)),
                          ),
                        ))
                    .toList(),
              ),
            ],
          );
        },
      );
      if (time == null || !mounted) return;
      await _handleStatusUpdate(
        () => _updateOrderStatus(OrderStatus.PREPARING, readyTime: time),
        'acceptOrder',
      );
    }

    Future<void> requestPickup() async {
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '픽업 요청 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      await _handleStatusUpdate(
          () => _updateOrderStatus(OrderStatus.READY), 'requestPickup');
    }

    Future<void> completeOrder() async {
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '주문 완료버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      await _handleStatusUpdate(
          () => _updateOrderStatus(OrderStatus.DONE), 'completeOrder');
    }

    // 주문 취소 — 확인 다이얼로그 내부에서 진행 인디케이터가 표시되도록 onConfirm 으로
    // _updateOrderStatus 를 직접 호출한다. _handleStatusUpdate 는 popup 자체를 pop 하므로
    // 여기서는 사용하지 않고, status 업데이트가 끝나 confirm 다이얼로그가 닫힌 뒤
    // popup 닫기/에러 표시를 직접 처리한다.
    Future<void> cancelOrder() async {
      final currentOrder = ref.read(orderDetailProvider).order;
      if (currentOrder == null) return;
      const String actionId = 'cancelOrder';
      final orderInfo =
          'displayNum=${currentOrder.displayNum}, simpleNum=${currentOrder.shopOrderNo}, orderId=${currentOrder.orderId}';
      logToFile(tag: LogTag.UI_ACTION, message: '주문 취소버튼: $orderInfo');

      bool isKioskOrder(OrderModel o) => o.source == 'WALD_KIOSK';

      if (isKioskOrder(currentOrder)) {
        CommonDialog.showInfoDialog(
            context: context,
            title: t.order_detail.dialog_kiosk_cancel_title,
            confirmText: t.common.confirm,
            content: t.order_detail.dialog_kiosk_cancel_content);
        return;
      }

      bool success = false;
      String? errorMessage;
      await CommonDialog.showConfirmDialog(
        context: context,
        title: t.order_detail.btn_order_cancel,
        cancelText: t.common.close,
        confirmText: t.order_detail.btn_order_cancel,
        content: t.order_detail
            .dialog_cancel_confirm_content(n: currentOrder.displayNum),
        onConfirm: () async {
          try {
            success = await _updateOrderStatus(OrderStatus.CANCELLED);
            if (success) {
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '상태 변경 성공: action=$actionId, $orderInfo');
            } else {
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '상태 변경 실패: action=$actionId, $orderInfo');
              errorMessage = t.order_detail.status_update_fail;
            }
          } catch (e, s) {
            logToFile(
                tag: LogTag.UI_ACTION,
                message: '상태 변경 오류: action=$actionId, $orderInfo, error=$e');
            errorMessage = e is ApiException ? e.message : '오류 발생: $e';
            logger.e('상태 업데이트 처리 중 오류', error: e, stackTrace: s);
          }
        },
      );

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
        await Future.delayed(const Duration(milliseconds: 300));
      } else if (errorMessage != null) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error_title,
          content: errorMessage!,
        );
      }
    }

    // 주문 취소 버튼은 자체 인디케이터를 표시하지 않는다 — 클릭 즉시 확인 다이얼로그가
    // 떠 있고, 진행 인디케이터는 확인 다이얼로그의 confirm 버튼 쪽에서 표시된다.
    Widget cancelOrderBtn({bool isMainAction = false}) => ActionButtonShell(
          text: t.order_detail.btn_order_cancel,
          busy: false,
          isMainAction: isMainAction,
          onPressed: () {
            cancelOrder();
          },
        );

    Widget completeOrderBtn({bool isMainAction = false}) => AsyncActionButton(
          text: t.order_detail.btn_order_complete,
          isMainAction: isMainAction,
          onPressed: completeOrder,
        );

    final isFromHistory = widget.isFromHistory;
    logger.d(
        '현재 주문 상태: ${order.status}, isFromHistory: $isFromHistory, isKdsMode: $isKdsMode');

    if (isFromHistory) {
      final secondaryBtns = reprintButtons();
      if (order.status != OrderStatus.CANCELLED) {
        return (
          secondary: secondaryBtns,
          primary: cancelOrderBtn(isMainAction: true),
        );
      } else {
        return (
          secondary: secondaryBtns,
          primary: closeButton(isMainAction: true),
        );
      }
    }

    // KDS 모드 + READY: 픽업 탭 상세창. 재출력 버튼 노출.
    if (isKdsMode && order.status == OrderStatus.READY) {
      return (
        secondary: reprintButtons(),
        primary: completeOrderBtn(isMainAction: true),
      );
    }

    if (order.status == OrderStatus.NEW) {
      return (
        secondary: [
          ...reprintButtons(),
          cancelOrderBtn(),
        ],
        primary: AsyncActionButton(
          text: t.order_detail.btn_order_accept,
          isMainAction: true,
          onPressed: acceptOrder,
        ),
      );
    }

    if (order.status == OrderStatus.PREPARING) {
      // KDS 진행탭 전용: 재출력만 노출 (주문취소·주문완료 버튼은 의도적으로 숨김).
      if (widget.isFromKds &&
          !widget.isFromAllTab &&
          !widget.isFromCompletedOrCancelled) {
        return (
          secondary: reprintButtons(),
          primary: AsyncActionButton(
            text: t.order_detail.btn_pickup_request,
            isMainAction: true,
            onPressed: requestPickup,
          ),
        );
      }
      return (
        secondary: [
          ...reprintButtons(),
          cancelOrderBtn(),
          completeOrderBtn(),
        ],
        primary: AsyncActionButton(
          text: t.order_detail.btn_pickup_request,
          isMainAction: true,
          onPressed: requestPickup,
        ),
      );
    }

    if (order.status == OrderStatus.READY) {
      return (
        secondary: reprintButtons(),
        primary: completeOrderBtn(isMainAction: true),
      );
    }

    // DONE / 기타
    return (
      secondary: reprintButtons(),
      primary: closeButton(isMainAction: true),
    );
  }
}

// ─── 상태 pill ────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final OrderModel order;

  const _StatusPill({required this.order});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final palette = AppStyles.statusPalette(order.status);
    final label = switch (order.status) {
      OrderStatus.NEW => t.order.new_order,
      OrderStatus.PREPARING => t.order.preparing,
      OrderStatus.READY => t.order.ready,
      OrderStatus.DONE => t.order.done,
      OrderStatus.CANCELLED => t.order.cancelled,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: AppRadius.bSm,
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySm.copyWith(
          color: palette.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── 소스 pill ────────────────────────────────────────────────────────────────

class _SourcePill extends StatelessWidget {
  final String source;

  const _SourcePill({required this.source});

  @override
  Widget build(BuildContext context) {
    final ({String label, Color bg, Color fg})? spec = switch (source) {
      'WALD_APPFIT' => (
          label: 'APP',
          bg: AppStyles.kAppOrderBg,
          fg: AppStyles.kAppOrderFg,
        ),
      'WALD_KIOSK' => (
          label: 'KIOSK',
          bg: AppStyles.kBlueAlpha,
          fg: AppStyles.kBlue,
        ),
      _ => null,
    };

    if (spec == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: AppRadius.bSm,
      ),
      child: Text(
        spec.label,
        style: AppTextStyles.bodySm.copyWith(
          color: spec.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── 매장/포장 pill ───────────────────────────────────────────────────────────

class _OrderTypePill extends StatelessWidget {
  final String orderType;

  const _OrderTypePill({required this.orderType});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    // IN_SHOP=매장(보라), TAKE_OUT=포장(앰버).
    // _SourcePill 의 연두(APP)/파랑(KIOSK) 와 충돌하지 않는 색 풀에서 선택.
    final spec = switch (orderType.toUpperCase()) {
      'IN_SHOP' => (
          label: t.order.type_dine_in,
          bg: AppStyles.kSubAlpha,
          fg: AppStyles.kSub,
        ),
      'TAKE_OUT' => (
          label: t.order.type_takeout,
          bg: AppStyles.kAmberAlpha,
          fg: AppStyles.kAmber,
        ),
      _ => null,
    };

    if (spec == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: AppRadius.bSm,
      ),
      child: Text(
        spec.label,
        style: AppTextStyles.bodySm.copyWith(
          color: spec.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
