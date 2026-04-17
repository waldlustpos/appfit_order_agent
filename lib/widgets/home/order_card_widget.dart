import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../models/order_model.dart';
import '../order/order_detail_popup.dart';
import '../../providers/providers.dart';
import '../../utils/model_parse_utils.dart';
import '../../i18n/strings.g.dart';

class OrderCardWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onTap;

  const OrderCardWidget({
    Key? key,
    required this.order,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isCancelled = order.status == OrderStatus.CANCELLED;
    final bool isDone = order.status == OrderStatus.DONE;

    // KDS 모드 여부 확인
    final isKdsMode = ref.watch(kdsModeProvider);

    // KDS 모드일 때는 이미 상세 정보를 가지고 있으므로 order를 그대로 사용
    // 일반 모드일 때는 해당 주문만 선택적으로 구독 (다른 주문 변경 시 리빌드 방지)
    final orderToCheck = isKdsMode
        ? order
        : ref.watch(orderProvider.select(
            (state) => state.orders.firstWhere(
              (o) => o.orderId == order.orderId,
              orElse: () => order,
            ),
          ));

    // 상세 정보가 없는 경우 상세 정보 로드 시도 (중복 호출 방지)
    // 오늘 날짜이고 KDS 모드가 아닌 경우에만 상세정보 로드
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday = selectedDate == todayDateString();

    if (!isKdsMode &&
        isToday &&
        orderToCheck.orderMenuList.isEmpty &&
        order.orderId.isNotEmpty &&
        !ref.read(orderProvider.notifier).isOrderDetailLoading(order.orderId)) {
      // 비동기로 상세 정보 로드 시도 (UI 블로킹 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref
            .read(orderProvider.notifier)
            .isOrderDetailLoading(order.orderId)) {
          ref.read(orderProvider.notifier).fetchOrderDetail(order.orderId);
        }
      });
    }

    // 특정 상품코드 체크 - 한 번만 계산
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
                if (onTap != null) {
                  onTap!();
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
      builder: (context) => OrderDetailPopup(order: order),
    );
  }
}
