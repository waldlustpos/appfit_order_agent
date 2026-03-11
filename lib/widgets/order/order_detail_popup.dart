import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../../models/order_model.dart';
import '../../providers/providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'order_menu_list_widget.dart';
import 'order_payment_info_widget.dart';
import 'order_info_panel_widget.dart';

class OrderDetailPopup extends ConsumerStatefulWidget {
  final OrderModel order;
  final bool isFromHistory;
  final bool isFromKds; // KDS 모드 여부 추가
  final bool isFromCompletedOrCancelled; // 완료/취소 탭 여부 추가
  final bool isFromAllTab; // 전체 탭 여부 추가

  const OrderDetailPopup({
    Key? key,
    required this.order,
    this.isFromHistory = false,
    this.isFromKds = false, // KDS 모드 파라미터 추가
    this.isFromCompletedOrCancelled = false, // 완료/취소 탭 파라미터 추가
    this.isFromAllTab = false, // 전체 탭 파라미터 추가
  }) : super(key: key);

  @override
  ConsumerState<OrderDetailPopup> createState() => _OrderDetailPopupState();
}

class _OrderDetailPopupState extends ConsumerState<OrderDetailPopup> {
  late ScrollController _menuScrollController;

  // 초기 주문 상태를 저장하는 변수
  late final OrderModel _originalOrder;

  @override
  void initState() {
    super.initState();
    _menuScrollController = ScrollController();

    // 초기 상태를 저장
    _originalOrder = widget.order;
    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            '주문 상세 팝업창 열기: orderId=${_originalOrder.orderNo}, simpleNum=${_originalOrder.shopOrderNo}, displayNum=${_originalOrder.displayNum}');
    // initState에서 비동기 작업 예약
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

    // 상세 정보 로딩 여부 확인 (menus가 있어도 isDetailLoaded가 false일 수 있음 - 로직에 따라)
    // 하지만 isDetailLoaded가 true이면 확실히 로딩된 것.
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

  // 주문 상태 업데이트 처리 함수
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
        // OrderProvider의 orders 리스트만 업데이트하고, OrderDetail 상태는 업데이트하지 않음
        if (!widget.isFromHistory) {
          final updatedOrder = currentOrder.copyWith(
            status: newStatus,
            orderStatus: _getStatusCode(newStatus),
            updateTime: DateTime.now(),
          );

          // 주문 취소의 경우 processOrderOutput 호출하지 않음 (cancelOrder에서 이미 취소 영수증 출력)
          if (newStatus == OrderStatus.PREPARING) {
            orderNotifier.processOrderOutput(updatedOrder, playSound: false);
          }

          // 팝업이 닫힌 후에 리스트 업데이트가 적용되도록 지연
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

  // 상태 업데이트 핸들러
  Future<void> _handleStatusUpdate(
      Future<bool> Function() updateFunction, String actionId) async {
    final orderDetailNotifier = ref.read(orderDetailProvider.notifier);
    if (ref.read(orderDetailProvider).loadingActionId != null) return;

    orderDetailNotifier.setLoadingAction(actionId);

    String? errorMessage;
    try {
      final success = await updateFunction();
      if (success) {
        if (mounted) {
          // 팝업 닫기 전에 로딩 상태 초기화
          orderDetailNotifier.setLoadingAction(null);

          // 즉시 팝업 닫기
          Navigator.of(context).pop();

          // 연타 방지를 위한 딜레이
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } else {
        errorMessage = t.order_detail.status_update_fail;
      }
    } catch (e, s) {
      errorMessage = '오류 발생: $e';
      logger.e('상태 업데이트 처리 중 오류', error: e, stackTrace: s);
    } finally {
      if (mounted) {
        // 에러 발생 시에만 로딩 상태 초기화 (성공 시에는 이미 위에서 초기화됨)
        if (errorMessage != null) {
          orderDetailNotifier.setLoadingAction(null);

          CommonDialog.showInfoDialog(
            context: context,
            title: t.common.error_title,
            content: errorMessage,
          );
        }
      } else {
        // 컴포넌트가 언마운트된 경우에도 로딩 상태 초기화
        orderDetailNotifier.setLoadingAction(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // OrderDetailProvider의 상태 변경은 감시하되, 주문 상태는 초기값 사용
    final orderDetailState = ref.watch(orderDetailProvider);
    final order = orderDetailState.order?.copyWith(
      status: _originalOrder.status,
      orderStatus: _originalOrder.orderStatus,
    );

    if (order == null) {
      return const Dialog(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Dialog(
      backgroundColor: AppStyles.gray1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: orderDetailState.isLoading
            ? _buildLoadingState()
            : orderDetailState.errorMessage != null
                ? _buildErrorState(orderDetailState.errorMessage!)
                : _buildContent(order, orderDetailState.loadingActionId),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
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
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(t.order_detail.error_prefix(error: errorMessage),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(t.common.refresh),
            onPressed: _fetchOrderDetailIfNeeded,
            style: AppStyles.primaryButton(),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.close),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(OrderModel order, String? loadingActionId) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, order),
        const SizedBox(height: 20),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: OrderMenuListWidget(
                  menus: order.orderMenuList,
                  scrollController: _menuScrollController,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 1,
                child: OrderPaymentInfoWidget(
                  totalAmount: order.totalAmount,
                  discountAmount: order.discountAmount,
                  paymentAmount: order.paymentAmount,
                ),
              ),
              const SizedBox(width: 20),
              OrderInfoPanelWidget(order: order),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildFooter(context, order, loadingActionId),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, OrderModel order) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            t.order.count_items(n: int.tryParse(order.orderCount) ?? 0),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 35),
            splashRadius: 35,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }


  Widget _buildFooter(
      BuildContext context, OrderModel order, String? loadingActionId) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _buildActionButtons(order),
      ),
    );
  }

  List<Widget> _buildActionButtons(OrderModel order) {
    final orderDetailState = ref.watch(orderDetailProvider);
    final Widget spacer = const SizedBox(width: 8);
    final isSubDisplay = ref.read(preferenceServiceProvider).getSubDisplay();

    // 완료/취소 탭인 경우 닫기 버튼만 표시
    if (widget.isFromCompletedOrCancelled) {
      return [
        _buildButton(t.common.close,
            onPressed: () => Navigator.of(context).pop(), actionId: 'close'),
      ];
    }

    // KDS 모드인 경우
    if (widget.isFromKds) {
      // 서브디스플레이이고 전체 탭에서 호출된 경우 닫기 버튼만 표시
      if (isSubDisplay && widget.isFromAllTab) {
        return [
          _buildButton(t.common.close,
              onPressed: () => Navigator.of(context).pop(), actionId: 'close'),
        ];
      }

      // 픽업 요청 처리 함수
      Future<void> requestPickup() async {
        logToFile(
            tag: LogTag.UI_ACTION,
            message:
                'KDS 픽업 요청 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
        await _handleStatusUpdate(
            () => _updateOrderStatus(OrderStatus.READY), 'requestPickup');
      }

      return [
        _buildButton(t.common.close,
            onPressed: () => Navigator.of(context).pop(), actionId: 'close'),
        if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
          spacer,
          _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
            if (ref.read(orderDetailProvider).loadingActionId != null) return;
            // 로딩 상태 표시 대신 로그 출력 및 실행
            logToFile(
                tag: LogTag.UI_ACTION,
                message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
            await ref.read(outputAppServiceProvider).printOrderLabels(order);
          }, actionId: 'reprintLabel'),
        ],
        spacer,
        const SizedBox(width: 20),
        _buildButton(t.order_detail.btn_pickup_request,
            onPressed: requestPickup,
            actionId: 'requestPickup',
            isMainAction: true),
      ];
    }

    // 주문 접수 처리 함수 - 준비 시간 선택 다이얼로그 표시
    Future<void> acceptOrder() async {
      final orderDetailState = ref.read(orderDetailProvider);
      if (orderDetailState.loadingActionId != null) return;
      logToFile(tag: LogTag.UI_ACTION, message: '주문 접수 버튼: $order');
      // 준비 시간 선택 다이얼로그 표시
      showDialog(
        context: context,
        builder: (BuildContext timeContext) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t.order_detail.time_select_title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, size: 24),
                  splashRadius: 20,
                  onPressed: () => Navigator.of(timeContext).pop(),
                ),
              ],
            ),
            content: Text(t.order_detail.time_select_content),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.all(20),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['5', '10', '15']
                    .map((time) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: ElevatedButton(
                            style: AppStyles.primaryButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              minimumSize: const Size(90, 48),
                              elevation: 2,
                            ).copyWith(
                              textStyle: const WidgetStatePropertyAll(
                                TextStyle(fontSize: 16),
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

    // 픽업 요청 처리 함수
    Future<void> requestPickup() async {
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '픽업 요청 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      await _handleStatusUpdate(
          () => _updateOrderStatus(OrderStatus.READY), 'requestPickup');
    }

    // 주문 완료 처리 함수
    Future<void> completeOrder() async {
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '주문 완료버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      await _handleStatusUpdate(
          () => _updateOrderStatus(OrderStatus.DONE), 'completeOrder');
    }

    // 주문 취소 처리 함수
    Future<void> cancelOrder() async {
      final orderDetailState = ref.read(orderDetailProvider);
      if (orderDetailState.loadingActionId != null) return;

      final order = orderDetailState.order;
      if (order == null) return;

      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '주문 취소버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');

      bool isKioskOrder(OrderModel order) {
        return order.userId == '3740002700000000' ||
            (order.paymentType.contains('KIOSK'));
      }

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
          title: t.order_detail.btn_order_cancel, // 주문 취소
          cancelText: t.common.close,
          confirmText: t.order_detail.btn_order_cancel,
          content: t.order_detail
              .dialog_cancel_confirm_content(n: order.displayNum));
      if (result == true) {
        await _handleStatusUpdate(
            () => _updateOrderStatus(OrderStatus.CANCELLED), 'cancelOrder');
      }
    }

    // 픽업 재요청 처리 함수
    Future<void> reRequestPickup() async {
      final orderDetailState = ref.read(orderDetailProvider);
      if (orderDetailState.loadingActionId != null) return;

      final order = orderDetailState.order;
      if (order == null) return;
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '픽업 재요청 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      final result = await CommonDialog.showConfirmDialog(
          context: context,
          title: t.order_detail.dialog_repickup_confirm_title,
          content: t.order_detail
              .dialog_repickup_confirm_content(n: order.displayNum));
      if (result == true) {
        await _handleStatusUpdate(
            () => _updateOrderStatus(OrderStatus.READY), 'reRequestPickup');
      }
    }

    // 미픽업 처리 함수
    Future<void> notPickedUp() async {
      final orderDetailState = ref.read(orderDetailProvider);
      if (orderDetailState.loadingActionId != null) return;

      final order = orderDetailState.order;
      if (order == null) return;
      logToFile(
          tag: LogTag.UI_ACTION,
          message:
              '미픽업 처리 버튼: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
      final result = await CommonDialog.showConfirmDialog(
          context: context,
          title: t.order_detail.dialog_not_picked_up_confirm_title,
          content: t.order_detail
              .dialog_not_picked_up_confirm_content(n: order.displayNum));
      if (result == true) {
        await _handleStatusUpdate(
            () => _updateOrderStatus(OrderStatus.CANCELLED), 'notPickedUp');
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

        // 라벨 프린터 사용 설정 확인 후 라벨 출력 (printOrderLabels 내부에서 재확인함)
        await ref.read(orderProvider.notifier).printOrderLabels(order);

        // 성공 후에도 일정 시간 동안 버튼 비활성화 유지 (연타 방지)
        if (mounted) {
          // 연타 방지를 위해 성공 후에도 약간의 시간 동안 로딩 상태 유지
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      } catch (e, s) {
        errorMessage = t.order_detail.print_receipt_fail(error: e.toString());
        logger.e('영수증 출력 실패', error: e, stackTrace: s);
      } finally {
        if (mounted) {
          // 로딩 상태 해제
          orderDetailNotifier.setLoadingAction(null);
          if (errorMessage != null) {
            CommonDialog.showInfoDialog(
              context: context,
              title: t.common.error_title, // 혹은 다른 에러 타이틀
              content: errorMessage,
            );
          }
        }
      }
    }

    // isFromHistory 변수를 읽기 전용 속성으로 가져옴 (OrderHistoryProvider 의존성 제거)
    final isFromHistory = widget.isFromHistory;

    // 주문 상태를 출력하여 디버깅
    logger.d(
        '현재 주문 상태: ${order.status}, isFromHistory: $isFromHistory, isSubDisplay: $isSubDisplay');

    if (isFromHistory) {
      if (order.status != OrderStatus.CANCELLED) {
        return [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
            spacer,
            _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
              if (ref.read(orderDetailProvider).loadingActionId != null) {
                return;
              }
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
              await ref.read(outputAppServiceProvider).printOrderLabels(order);
            }, actionId: 'reprintLabel'),
          ],
          spacer,
          const SizedBox(
            width: 20,
          ),
          _buildButton(t.order_detail.btn_order_cancel,
              onPressed: cancelOrder,
              actionId: 'cancelOrder',
              isMainAction: true),
        ];
      } else {
        return [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
            spacer,
            _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
              if (ref.read(orderDetailProvider).loadingActionId != null) {
                return;
              }
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
              await ref.read(outputAppServiceProvider).printOrderLabels(order);
            }, actionId: 'reprintLabel'),
          ],
          spacer,
          const SizedBox(
            width: 20,
          ),
          _buildButton(t.common.close,
              onPressed: () => Navigator.of(context).pop(),
              actionId: 'close',
              isMainAction: true),
        ];
      }
    } else {
      // 서브디스플레이이고 상품준비완료 상태일 때는 주문완료 버튼만 표시
      if (isSubDisplay && order.status == OrderStatus.READY) {
        return [
          _buildButton(t.order_detail.btn_order_complete,
              onPressed: completeOrder,
              actionId: 'completeOrder',
              isMainAction: true),
        ];
      }

      // NEW 상태인 경우 주문접수 버튼 추가
      if (order.status == OrderStatus.NEW) {
        return [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
            spacer,
            _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
              if (ref.read(orderDetailProvider).loadingActionId != null) {
                return;
              }
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
              await ref.read(outputAppServiceProvider).printOrderLabels(order);
            }, actionId: 'reprintLabel'),
          ],
          spacer,
          _buildButton(t.order_detail.btn_order_cancel,
              onPressed: cancelOrder, actionId: 'cancelOrder'),
          spacer,
          const SizedBox(
            width: 20,
          ),
          _buildButton(t.order_detail.btn_order_accept,
              onPressed: acceptOrder,
              actionId: 'acceptOrder',
              isMainAction: true),
        ];
      } else if (order.status == OrderStatus.PREPARING) {
        // KDS 모드이고 진행탭에서 열린 경우 픽업 요청 버튼을 더 강조
        if (widget.isFromKds &&
            !widget.isFromAllTab &&
            !widget.isFromCompletedOrCancelled) {
          return [
            _buildButton(t.order_detail.btn_receipt_reprint,
                onPressed: printReceipt, actionId: 'printReceipt'),
            spacer,
            _buildButton(t.order_detail.btn_order_cancel,
                onPressed: cancelOrder, actionId: 'cancelOrder'),
            spacer,
            _buildButton(t.order_detail.btn_order_complete,
                onPressed: completeOrder, actionId: 'completeOrder'),
            spacer,
            const SizedBox(
              width: 20,
            ),
            _buildKdsPickupButton(t.order_detail.btn_pickup_request,
                requestPickup), // KDS 전용 픽업 버튼
          ];
        } else {
          return [
            _buildButton(t.order_detail.btn_receipt_reprint,
                onPressed: printReceipt, actionId: 'printReceipt'),
            if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
              spacer,
              _buildButton(t.order_detail.btn_label_reprint,
                  onPressed: () async {
                if (ref.read(orderDetailProvider).loadingActionId != null) {
                  return;
                }
                logToFile(
                    tag: LogTag.UI_ACTION,
                    message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
                await ref
                    .read(outputAppServiceProvider)
                    .printOrderLabels(order);
              }, actionId: 'reprintLabel'),
            ],
            spacer,
            _buildButton(t.order_detail.btn_order_cancel,
                onPressed: cancelOrder, actionId: 'cancelOrder'),
            spacer,
            _buildButton(t.order_detail.btn_order_complete,
                onPressed: completeOrder, actionId: 'completeOrder'),
            spacer,
            const SizedBox(
              width: 20,
            ),
            _buildButton(t.order_detail.btn_pickup_request,
                onPressed: requestPickup,
                actionId: 'requestPickup',
                isMainAction: true),
          ];
        }
      } else if (order.status == OrderStatus.READY) {
        return [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
            spacer,
            _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
              if (ref.read(orderDetailProvider).loadingActionId != null) {
                return;
              }
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
              await ref.read(outputAppServiceProvider).printOrderLabels(order);
            }, actionId: 'reprintLabel'),
          ],

          //픽업 재요청 -> 매머드에서만 사용
          /*spacer,
          _buildButton('픽업 재요청',
              onPressed: reRequestPickup, actionId: 'reRequestPickup'),*/

          //미픽업 버튼은 매머드 전용
          /*spacer,
          _buildButton('미픽업', onPressed: notPickedUp, actionId: 'notPickedUp'),*/
          spacer,
          const SizedBox(
            width: 20,
          ),
          _buildButton(t.order_detail.btn_order_complete,
              onPressed: completeOrder,
              actionId: 'completeOrder',
              isMainAction: true),
        ];
      } else {
        // 완료섹션이나 기타 상태
        List<Widget> buttons = [
          _buildButton(t.order_detail.btn_receipt_reprint,
              onPressed: printReceipt, actionId: 'printReceipt'),
          if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) ...[
            spacer,
            _buildButton(t.order_detail.btn_label_reprint, onPressed: () async {
              if (ref.read(orderDetailProvider).loadingActionId != null) {
                return;
              }
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '라벨 재출력 버튼 클릭: ${order.orderNo}');
              await ref.read(outputAppServiceProvider).printOrderLabels(order);
            }, actionId: 'reprintLabel'),
          ],
          spacer,
          const SizedBox(
            width: 20,
          ),
          _buildButton(t.common.close,
              onPressed: () => Navigator.of(context).pop(),
              actionId: 'close',
              isMainAction: true),
        ];

        return buttons;
      }
    }
  }

  // KDS 진행탭 전용 픽업 요청 버튼
  Widget _buildKdsPickupButton(String text, VoidCallback? onPressed) {
    final providerState = ref.read(orderDetailProvider);
    final bool isLoading = providerState.loadingActionId == 'requestPickup';
    final bool isActionInProgress = providerState.loadingActionId != null;

    return ElevatedButton(
      style: AppStyles.primaryButton(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        minimumSize: const Size(120, 48),
        elevation: 3,
      ).copyWith(
        backgroundColor: const WidgetStatePropertyAll(AppStyles.kSub),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Widget _buildButton(String text,
      {required VoidCallback? onPressed,
      required String actionId,
      bool isMainAction = false}) {
    // 현재 팝업의 주문 ID를 확인
    final currentOrderId = _originalOrder.orderId;

    // 현재 진행 중인 액션이 이 팝업의 주문에 관한 것인지 확인
    final providerState = ref.read(orderDetailProvider);
    final bool isLoading = providerState.loadingActionId == actionId;
    final bool isActionInProgress = providerState.loadingActionId != null;

    // 주문 ID와 함께 로깅하여 디버깅에 도움이 되도록 함
    if (isActionInProgress) {
      logger.d(
          'Button build: orderId=$currentOrderId, actionId=$actionId, inProgress=${providerState.loadingActionId}');
    }

    return ElevatedButton(
      style: isMainAction
          ? AppStyles.primaryButton(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              minimumSize: const Size(120, 48),
              elevation: 2,
            ).copyWith(
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 16)),
            )
          : AppStyles.outlinedButton(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(100, 48),
              borderColor: Colors.grey.shade300,
            ).copyWith(
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 16)),
            ),
      // 액션 진행 중이면 모든 버튼 비활성화
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
