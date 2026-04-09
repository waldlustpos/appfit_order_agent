import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../models/order_model.dart';
import '../../providers/kds_unified_providers.dart';
import '../order/order_detail_popup.dart';
import '../../providers/providers.dart';
import '../../utils/logger.dart';
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
    final bool isAccepted = order.status == OrderStatus.PREPARING;
    final bool isCompleted =
        order.status == OrderStatus.DONE || order.status == OrderStatus.READY;

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
    // orderToCheck가 원본 order와 동일한 객체인 경우에도 안전하게 처리
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
    Color backgroundColor;
    Color orderNumberColor;
    Color countColor;
    bool showStrikethrough = false; // kept for future use (cancelled state)
    bool showCountStrikethrough = false;

    if (isCancelled) {
      backgroundColor = AppStyles.kRedAlpha;
      orderNumberColor = AppStyles.kRed;
      countColor = Colors.grey[600]!; // gray6
      showStrikethrough = true; // 취소건에만 주문번호 취소선
      showCountStrikethrough = true; // 취소건에만 개수 취소선
    } else {
      backgroundColor = AppStyles.kBlueAlpha;
      orderNumberColor = AppStyles.kBlue;
      countColor = Colors.black;
      showStrikethrough = false; // 접수건에는 취소선 없음
      showCountStrikethrough = false; // 접수건에는 취소선 없음

      // 매장/포장/매장+포장에 따른 색상 변경
      if (orderPrefix == t.order.type_dine_in) {
        backgroundColor = AppStyles.kSubAlpha;
        orderNumberColor = AppStyles.kSub;
      } else if (orderPrefix == t.order.type_both) {
        backgroundColor = AppStyles.gray2;
        orderNumberColor = AppStyles.gray9;
      }
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Card(
        elevation: 0,
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(
            color: Colors.grey[400]!, // 모든 상태에서 동일한 테두리 색상
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(4),
        child: InkWell(
          onTap: () {
            if (onTap != null) {
              onTap!();
            } else {
              _showOrderDetailPopup(context);
            }
          },
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (orderPrefix.isNotEmpty)
                  Text(
                    orderPrefix,
                    style: TextStyle(
                      fontSize: AppStyles.kOrderNumberSize,
                      fontWeight: FontWeight.bold,
                      color: orderNumberColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                Text(
                  order.displayNum,
                  style: TextStyle(
                    fontSize: AppStyles.kOrderNumberSize,
                    fontWeight: FontWeight.bold,
                    color: orderNumberColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  t.order.count(n: int.tryParse(order.orderCount) ?? 1),
                  style: TextStyle(
                    fontSize: AppStyles.kSectionCountSize,
                    fontWeight: FontWeight.normal,
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
    );
  }

  void _showOrderDetailPopup(BuildContext context) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => OrderDetailPopup(order: order),
    );
  }
}
