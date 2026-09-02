import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/widgets/order/order_detail_popup.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderCardWidget extends ConsumerStatefulWidget {
  final OrderModel order;
  final VoidCallback? onTap;
  // 호출 진입점에서 명시 전달. KDS 모드 분기에 따라 상세 fetch / select 동작이 갈린다.
  // 카드 단위 ref.watch(kdsModeProvider) 를 제거해 모드 토글 시 카드 N개 일제 리빌드 방지.
  final bool isKdsMode;

  const OrderCardWidget({
    super.key,
    required this.order,
    this.onTap,
    this.isKdsMode = false,
  });

  @override
  ConsumerState<OrderCardWidget> createState() => _OrderCardWidgetState();
}

class _OrderCardWidgetState extends ConsumerState<OrderCardWidget> {
  // 메인 모드 카드는 상세(menus)를 프리페치하지 않는다. 상세는 카드 탭 시 팝업이
  // 온디맨드로 조회한다(OrderDetailPopup._fetchOrderDetailIfNeeded). 매장/포장 프리픽스는
  // 목록의 orderType 필드로 판별(OrderModel.detectSpecialProductType)하므로 상세가 필요 없다.
  // KDS 모드는 KdsOrderCard 쪽에서 상세를 채운다.
  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isKdsMode = widget.isKdsMode;
    final bool isCancelled = order.status == OrderStatus.CANCELLED;
    final bool isDone = order.status == OrderStatus.DONE;
    final bool isNoShow = order.status == OrderStatus.NO_SHOW;

    // KDS 모드일 때는 이미 상세 정보를 가지고 있으므로 order를 그대로 사용.
    // 일반 모드일 때는 ID 인덱스 기반 family 로 해당 주문만 선택적으로 구독한다
    // (O(N²) firstWhere 제거 + 다른 주문 변경 시 리빌드 방지).
    final orderToCheck = isKdsMode
        ? order
        : (ref.watch(orderByIdProvider(order.orderId)) ?? order);

    // 상태별 색상 및 스타일 결정.
    // '주문 출처별 색상' 설정 ON 이면 앱/키오스크 출처 색으로 칠한다.
    // 매장/포장 구분은 카드에 표시하지 않으므로(다이얼로그 배지에서만 확인), 출처색 OFF
    // 일 때는 매장/포장 무관 기본 팔레트(SpecialProductType.none)를 사용한다.
    final useSourceColor = ref.watch(orderSourceColorProvider);
    // 미픽업은 완료와 같은 종결 표현(muted 배경 + 회색 번호)을 쓰되, 배경만
    // 한 톤 진한 회색으로 갈린다. 메인 카드는 번호·수량만 있는 정사각이라 배지
    // 자리가 없어서, 이 배경색이 완료와 미픽업을 가르는 유일한 신호다.
    final isSettled = isDone || isNoShow;
    final palette = useSourceColor
        ? AppStyles.orderSourcePalette(orderToCheck.source,
            isCancelled: isCancelled, isNoShow: isNoShow, muted: isSettled)
        : AppStyles.orderPalette(SpecialProductType.none,
            isCancelled: isCancelled, isNoShow: isNoShow, muted: isSettled);
    final backgroundColor = palette.bg;
    final orderNumberColor =
        isCancelled || isSettled ? AppStyles.gray6 : palette.fg;
    final countColor =
        isCancelled || isSettled ? AppStyles.gray6 : Colors.black;
    // 취소선은 취소 전용이다. 미픽업까지 그으면 둘을 가르는 신호가 사라진다.
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
