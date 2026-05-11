import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../models/order_model.dart';
import '../order/order_detail_popup.dart';
import '../../providers/providers.dart';
import '../../utils/model_parse_utils.dart';
import '../../i18n/strings.g.dart';

class OrderCardWidget extends ConsumerStatefulWidget {
  final OrderModel order;
  final VoidCallback? onTap;
  // 호출 진입점에서 명시 전달. KDS 모드 분기에 따라 상세 fetch / select 동작이 갈린다.
  // 카드 단위 ref.watch(kdsModeProvider) 를 제거해 모드 토글 시 카드 N개 일제 리빌드 방지.
  final bool isKdsMode;

  const OrderCardWidget({
    Key? key,
    required this.order,
    this.onTap,
    this.isKdsMode = false,
  }) : super(key: key);

  @override
  ConsumerState<OrderCardWidget> createState() => _OrderCardWidgetState();
}

class _OrderCardWidgetState extends ConsumerState<OrderCardWidget> {
  @override
  void initState() {
    super.initState();
    _maybeFetchDetail(widget.order);
  }

  @override
  void didUpdateWidget(OrderCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.orderId != oldWidget.order.orderId) {
      _maybeFetchDetail(widget.order);
    }
  }

  /// 상세 정보가 없는 경우 1회 로드 트리거. build 중이 아닌 라이프사이클 훅에서 호출한다.
  void _maybeFetchDetail(OrderModel order) {
    if (widget.isKdsMode) return;
    if (order.orderId.isEmpty) return;
    if (order.orderMenuList.isNotEmpty) return;
    final isToday = ref.read(selectedDateProvider) == todayDateString();
    if (!isToday) return;
    final notifier = ref.read(orderProvider.notifier);
    if (notifier.isOrderDetailLoading(order.orderId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (notifier.isOrderDetailLoading(order.orderId)) return;
      notifier.fetchOrderDetail(order.orderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isKdsMode = widget.isKdsMode;
    final bool isCancelled = order.status == OrderStatus.CANCELLED;
    final bool isDone = order.status == OrderStatus.DONE;

    // KDS 모드일 때는 이미 상세 정보를 가지고 있으므로 order를 그대로 사용.
    // 일반 모드일 때는 ID 인덱스 기반 family 로 해당 주문만 선택적으로 구독한다
    // (O(N²) firstWhere 제거 + 다른 주문 변경 시 리빌드 방지).
    final orderToCheck = isKdsMode
        ? order
        : (ref.watch(orderByIdProvider(order.orderId)) ?? order);

    // 매장/포장/매장+포장 프리픽스 계산
    final type = orderToCheck.detectSpecialProductType();
    String orderPrefix = '';
    switch (type) {
      case SpecialProductType.dineIn:
        orderPrefix = t.order.type_dine_in;
        break;
      case SpecialProductType.takeout:
        orderPrefix = t.order.type_takeout;
        break;
      case SpecialProductType.both:
        orderPrefix = t.order.type_both;
        break;
      case SpecialProductType.none:
        orderPrefix = '';
        break;
    }

    // 상태별 색상 및 스타일 결정
    final palette =
        AppStyles.orderPalette(type, isCancelled: isCancelled, muted: isDone);
    final backgroundColor = palette.bg;
    final orderNumberColor =
        isCancelled || isDone ? AppStyles.gray6 : palette.fg;
    final countColor = isCancelled || isDone ? AppStyles.gray6 : Colors.black;
    final showCountStrikethrough = isCancelled;

    // 상태별 보더 및 그림자
    final borderColor = _borderForStatus(order.status, isCancelled);
    final borderWidth = _borderWidthForStatus(order.status, isCancelled);
    final shadows = order.status == OrderStatus.NEW ? AppElevation.soft : null;

    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.bLg,
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: shadows,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.bLg,
            child: InkWell(
              onTap: () {
                if (widget.onTap != null) {
                  widget.onTap!();
                } else {
                  _showOrderDetailPopup(context);
                }
              },
              borderRadius: AppRadius.bLg,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (orderPrefix.isNotEmpty)
                      Text(
                        orderPrefix,
                        style: AppTextStyles.body.copyWith(
                          fontSize: AppStyles.kOrderNumberSize,
                          fontWeight: FontWeight.bold,
                          color: orderNumberColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    Text(
                      order.displayNum,
                      style: AppTextStyles.body.copyWith(
                        fontSize: AppStyles.kOrderNumberSize,
                        fontWeight: FontWeight.bold,
                        color: orderNumberColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      t.order.count(n: int.tryParse(order.orderCount) ?? 1),
                      style: AppTextStyles.bodySm.copyWith(
                        fontSize: AppStyles.kSectionCountSize,
                        color: countColor,
                        decoration: showCountStrikethrough
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 주문 상태에 따른 보더 색상 반환
  Color _borderForStatus(OrderStatus status, bool isCancelled) {
    if (isCancelled) return AppStyles.kRed;
    switch (status) {
      case OrderStatus.NEW:
        return AppStyles.kMainColor;
      case OrderStatus.PREPARING:
      case OrderStatus.READY:
      case OrderStatus.DONE:
      default:
        return AppStyles.gray3;
    }
  }

  /// 주문 상태에 따른 보더 두께 반환
  double _borderWidthForStatus(OrderStatus status, bool isCancelled) {
    if (isCancelled) return 1.0;
    switch (status) {
      case OrderStatus.NEW:
        return 1.5;
      default:
        return 1.0;
    }
  }

  void _showOrderDetailPopup(BuildContext context) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => OrderDetailPopup(order: widget.order),
    );
  }
}
