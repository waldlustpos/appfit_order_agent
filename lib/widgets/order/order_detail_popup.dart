import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../../models/order_model.dart';
import '../../providers/providers.dart';
import '../../providers/currency_provider.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'order_menu_list_widget.dart';
import 'order_payment_info_widget.dart';
import 'order_info_panel_widget.dart';

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
    final orderDetailNotifier = ref.read(orderDetailProvider.notifier);
    if (ref.read(orderDetailProvider).loadingActionId != null) return;

    orderDetailNotifier.setLoadingAction(actionId);

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
          orderDetailNotifier.setLoadingAction(null);
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
      if (mounted) {
        if (errorMessage != null) {
          orderDetailNotifier.setLoadingAction(null);
          CommonDialog.showInfoDialog(
            context: context,
            title: t.common.error_title,
            content: errorMessage,
          );
        }
      } else {
        orderDetailNotifier.setLoadingAction(null);
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
                : _buildContent(
                    order, orderDetailState.loadingActionId, currencyUnit),
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

  Widget _buildContent(
      OrderModel order, String? loadingActionId, String currencyUnit) {
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
              OrderInfoPanelWidget(order: order),
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
            _StatusPill(order: order),
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
    final orderDetailState = ref.watch(orderDetailProvider);
    final isSubDisplay = ref.read(preferenceServiceProvider).getSubDisplay();

    Widget close() => _buildButton(
          t.common.close,
          onPressed: () => Navigator.of(context).pop(),
          actionId: 'close',
        );

    // 완료/취소 탭: 닫기 단일 버튼
    if (widget.isFromCompletedOrCancelled) {
      return (secondary: [], primary: close());
    }

    // KDS 모드
    if (widget.isFromKds) {
      if (isSubDisplay && widget.isFromAllTab) {
        return (secondary: [], primary: close());
      }

      Future<void> requestPickup() async {
        logToFile(
            tag: LogTag.UI_ACTION,
            message:
                'KDS 픽업 요청 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
        await _handleStatusUpdate(
            () => _updateOrderStatus(OrderStatus.READY), 'requestPickup');
      }

      return (
        secondary: [
          close(),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter())
            _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
              if (ref.read(orderDetailProvider).loadingActionId != null) {
                return;
              }
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
              await ref
                  .read(outputAppServiceProvider)
                  .printOrderLabels(order, isReprint: true);
            }, actionId: 'reprintLabel'),
        ],
        primary: _buildButton(
          t.order_detail.btn_pickup_request,
          onPressed: requestPickup,
          actionId: 'requestPickup',
          isMainAction: true,
        ),
      );
    }

    // 준비 시간 선택 다이얼로그
    Future<void> acceptOrder() async {
      if (orderDetailState.loadingActionId != null) return;
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '주문 접수 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      showDialog(
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
                    .map((time) => Padding(
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
                                  message: '주문 접수 버튼 -> 시간선택 $time분');
                              Navigator.of(timeContext).pop();
                              _handleStatusUpdate(
                                  () => _updateOrderStatus(
                                      OrderStatus.PREPARING,
                                      readyTime: time),
                                  'acceptOrder');
                            },
                            child: Text(t.order_detail.minutes(n: time)),
                          ),
                        ))
                    .toList(),
              ),
            ],
          );
        },
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

    Future<void> cancelOrder() async {
      if (orderDetailState.loadingActionId != null) return;
      final order = orderDetailState.order;
      if (order == null) return;
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '주문 취소버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');

      bool isKioskOrder(OrderModel o) => o.source == 'WALD_KIOSK';

      if (isKioskOrder(order)) {
        CommonDialog.showInfoDialog(
            context: context,
            title: t.order_detail.dialog_kiosk_cancel_title,
            confirmText: t.common.confirm,
            content: t.order_detail.dialog_kiosk_cancel_content);
        return;
      }

      final result = await CommonDialog.showConfirmDialog(
          context: context,
          title: t.order_detail.btn_order_cancel,
          cancelText: t.common.close,
          confirmText: t.order_detail.btn_order_cancel,
          content: t.order_detail
              .dialog_cancel_confirm_content(n: order.displayNum));
      if (result == true) {
        await _handleStatusUpdate(
            () => _updateOrderStatus(OrderStatus.CANCELLED), 'cancelOrder');
      }
    }

    Future<void> printReceipt() async {
      if (orderDetailState.loadingActionId != null) return;
      final order = orderDetailState.order;
      if (order == null) return;
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '영수증 재출력 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      const String actionId = 'printReceipt';
      final orderDetailNotifier = ref.read(orderDetailProvider.notifier);
      orderDetailNotifier.setLoadingAction(actionId);
      String? errorMessage;
      try {
        final printService = ref.read(printServiceProvider);
        final bool isCancelled = (order.status == OrderStatus.CANCELLED);
        logger.i('영수증 재출력 요청: 주문 ID ${order.orderId}, 취소됨: $isCancelled');
        await printService.printOrderReceipt(
          order: order,
          type: 'receipt',
          isCancelReceipt: isCancelled,
        );
        await ref
            .read(orderProvider.notifier)
            .printOrderLabels(order, isReprint: true);
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      } catch (e, s) {
        errorMessage = t.order_detail.print_receipt_fail(error: e.toString());
        logger.e('영수증 출력 실패', error: e, stackTrace: s);
      } finally {
        if (mounted) {
          orderDetailNotifier.setLoadingAction(null);
          if (errorMessage != null) {
            CommonDialog.showInfoDialog(
              context: context,
              title: t.common.error_title,
              content: errorMessage,
            );
          }
        }
      }
    }

    Widget labelReprintBtn() => _buildButton(
          t.order_detail.btn_label_reprint,
          onPressed: () async {
            if (ref.read(orderDetailProvider).loadingActionId != null) return;
            logToFile(
                tag: LogTag.UI_ACTION,
                message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
            await ref
                .read(outputAppServiceProvider)
                .printOrderLabels(order, isReprint: true);
          },
          actionId: 'reprintLabel',
        );

    final isFromHistory = widget.isFromHistory;
    logger.d(
        '현재 주문 상태: ${order.status}, isFromHistory: $isFromHistory, isSubDisplay: $isSubDisplay');

    if (isFromHistory) {
      final secondaryBtns = [
        _buildButton(t.order_detail.btn_receipt_reprint,
            onPressed: printReceipt, actionId: 'printReceipt'),
        if (ref.read(preferenceServiceProvider).getUseLabelPrinter())
          labelReprintBtn(),
      ];
      if (order.status != OrderStatus.CANCELLED) {
        return (
          secondary: secondaryBtns,
          primary: _buildButton(
            t.order_detail.btn_order_cancel,
            onPressed: cancelOrder,
            actionId: 'cancelOrder',
            isMainAction: true,
          ),
        );
      } else {
        return (
          secondary: secondaryBtns,
          primary: _buildButton(
            t.common.close,
            onPressed: () => Navigator.of(context).pop(),
            actionId: 'close',
            isMainAction: true,
          ),
        );
      }
    }

    // 서브디스플레이 + READY
    if (isSubDisplay && order.status == OrderStatus.READY) {
      return (
        secondary: [],
        primary: _buildButton(
          t.order_detail.btn_order_complete,
          onPressed: completeOrder,
          actionId: 'completeOrder',
          isMainAction: true,
        ),
      );
    }

    if (order.status == OrderStatus.NEW) {
      return (
        secondary: [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter())
            labelReprintBtn(),
          _buildButton(t.order_detail.btn_order_cancel,
              onPressed: cancelOrder, actionId: 'cancelOrder'),
        ],
        primary: _buildButton(
          t.order_detail.btn_order_accept,
          onPressed: acceptOrder,
          actionId: 'acceptOrder',
          isMainAction: true,
        ),
      );
    }

    if (order.status == OrderStatus.PREPARING) {
      // KDS 진행탭 전용
      if (widget.isFromKds &&
          !widget.isFromAllTab &&
          !widget.isFromCompletedOrCancelled) {
        return (
          secondary: [
            _buildButton(t.order_detail.btn_receipt_reprint,
                onPressed: printReceipt, actionId: 'printReceipt'),
            _buildButton(t.order_detail.btn_order_cancel,
                onPressed: cancelOrder, actionId: 'cancelOrder'),
            _buildButton(t.order_detail.btn_order_complete,
                onPressed: completeOrder, actionId: 'completeOrder'),
          ],
          primary: _buildKdsPickupButton(
            t.order_detail.btn_pickup_request,
            requestPickup,
          ),
        );
      }
      return (
        secondary: [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter())
            labelReprintBtn(),
          _buildButton(t.order_detail.btn_order_cancel,
              onPressed: cancelOrder, actionId: 'cancelOrder'),
          _buildButton(t.order_detail.btn_order_complete,
              onPressed: completeOrder, actionId: 'completeOrder'),
        ],
        primary: _buildButton(
          t.order_detail.btn_pickup_request,
          onPressed: requestPickup,
          actionId: 'requestPickup',
          isMainAction: true,
        ),
      );
    }

    if (order.status == OrderStatus.READY) {
      return (
        secondary: [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter())
            labelReprintBtn(),
        ],
        primary: _buildButton(
          t.order_detail.btn_order_complete,
          onPressed: completeOrder,
          actionId: 'completeOrder',
          isMainAction: true,
        ),
      );
    }

    // DONE / 기타
    return (
      secondary: [
        _buildButton(t.order_detail.btn_receipt_reprint,
            onPressed: printReceipt, actionId: 'printReceipt'),
        if (ref.read(preferenceServiceProvider).getUseLabelPrinter())
          labelReprintBtn(),
      ],
      primary: _buildButton(
        t.common.close,
        onPressed: () => Navigator.of(context).pop(),
        actionId: 'close',
        isMainAction: true,
      ),
    );
  }

  Widget _buildKdsPickupButton(String text, VoidCallback? onPressed) {
    final providerState = ref.read(orderDetailProvider);
    final bool isLoading = providerState.loadingActionId == 'requestPickup';
    final bool isActionInProgress = providerState.loadingActionId != null;

    return ElevatedButton(
      style: AppStyles.primaryButton(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s32,
          vertical: AppSpacing.s12,
        ),
        minimumSize: const Size(120, 44),
        elevation: 2,
      ).copyWith(
        backgroundColor: const WidgetStatePropertyAll(AppStyles.kSub),
        textStyle: WidgetStatePropertyAll(
          AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      onPressed: isActionInProgress ? null : onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: isLoading ? 0.0 : 1.0,
            child: Text(text),
          ),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildButton(
    String text, {
    required VoidCallback? onPressed,
    required String actionId,
    bool isMainAction = false,
  }) {
    final currentOrderId = _originalOrder.orderId;
    final providerState = ref.read(orderDetailProvider);
    final bool isLoading = providerState.loadingActionId == actionId;
    final bool isActionInProgress = providerState.loadingActionId != null;

    if (isActionInProgress) {
      logger.d(
          'Button build: orderId=$currentOrderId, actionId=$actionId, inProgress=${providerState.loadingActionId}');
    }

    return ElevatedButton(
      style: isMainAction
          ? AppStyles.primaryButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(120, 44),
            ).copyWith(
              textStyle: WidgetStatePropertyAll(
                AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
            )
          : AppStyles.outlinedButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 44),
              borderColor: AppStyles.gray3,
            ).copyWith(
              textStyle: WidgetStatePropertyAll(
                AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
      onPressed: isActionInProgress ? null : onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: isLoading ? 0.0 : 1.0,
            child: Text(text),
          ),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
        ],
      ),
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
