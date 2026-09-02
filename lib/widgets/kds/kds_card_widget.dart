import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/card_types.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';

/// KDS 주문 카드 헤더.
///
/// - 주문번호: 가장 강한 위계 (titleSm, w600)
/// - 총 아이템 수: 보조 위계 (bodySm)로 격하
/// - 시간: 가장 가벼운 위계 (caption)
/// - 색상은 [AppStyles.orderPalette]가 제공하는 (배경, 전경) 팔레트 1쌍을 따른다.
class KdsCardHeaderWidget extends ConsumerWidget {
  final OrderModel order;
  final OrderModel detailedOrder;
  final CardType cardType;

  const KdsCardHeaderWidget({
    super.key,
    required this.order,
    required this.detailedOrder,
    required this.cardType,
  });

  int _totalItems(OrderModel order) {
    var total = 0;
    for (final menu in order.orderMenuList) {
      total += menu.qty;
    }
    return total;
  }

  /// 완료 탭에는 DONE 과 NO_SHOW 이 **섞여 있다**(미픽업 전용 탭이 없다).
  /// 그래서 완료 분기만은 cardType 이 아니라 실제 상태를 봐야 배경 워시가 갈린다.
  bool get _isNoShow => order.status == OrderStatus.NO_SHOW;

  OrderPalette _palette(bool useSourceColor) {
    // '주문 출처별 색상' 설정 ON 이면 매장/포장 색 대신 앱/키오스크 출처 색으로.
    if (useSourceColor) {
      final source = detailedOrder.source;
      return switch (cardType) {
        CardType.progress => AppStyles.orderSourcePalette(source),
        CardType.pickup => AppStyles.orderSourcePalette(source, muted: true),
        CardType.completed => AppStyles.orderSourcePalette(source,
            isNoShow: _isNoShow, muted: true),
        CardType.cancelled =>
          AppStyles.orderSourcePalette(source, isCancelled: true),
      };
    }
    // 매장/포장 구분은 카드에 표시하지 않으므로(다이얼로그 배지에서만) 기본 팔레트 사용.
    const type = SpecialProductType.none;
    return switch (cardType) {
      CardType.progress => AppStyles.orderPalette(type),
      CardType.pickup => AppStyles.orderPalette(type, muted: true),
      CardType.completed =>
        AppStyles.orderPalette(type, isNoShow: _isNoShow, muted: true),
      CardType.cancelled => AppStyles.orderPalette(type, isCancelled: true),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = _palette(ref.watch(orderSourceColorProvider));

    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.sm),
          topRight: Radius.circular(AppRadius.sm),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  order.displayNum,
                  style: AppTextStyles.titleSm.copyWith(color: palette.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                t.kds.total_items(n: _totalItems(detailedOrder)),
                style: AppTextStyles.bodySm.copyWith(color: palette.fg),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              Flexible(
                child: Text(
                  t.kds.order_time(
                      time: DateFormat('HH:mm:ss').format(order.orderedAt)),
                  style: AppTextStyles.caption.copyWith(color: AppStyles.gray6),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 완료 탭은 DONE 과 카드 색이 같으므로 **이 배지가 유일한 구분**이다.
              if (_isNoShow) ...[
                const SizedBox(width: AppSpacing.s4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppStyles.kNoShowAlpha,
                    borderRadius: AppRadius.bSm,
                  ),
                  child: Text(
                    t.order.no_show,
                    style: AppTextStyles.caption.copyWith(
                      color: AppStyles.kNoShow,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
