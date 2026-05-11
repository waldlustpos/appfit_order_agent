import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderInfoPanelWidget extends StatefulWidget {
  final OrderModel order;

  const OrderInfoPanelWidget({
    super.key,
    required this.order,
  });

  @override
  State<OrderInfoPanelWidget> createState() => _OrderInfoPanelWidgetState();
}

class _OrderInfoPanelWidgetState extends State<OrderInfoPanelWidget> {
  // 메모 영역 SingleChildScrollView 와 RawScrollbar 를 attach 하는 전용 controller.
  // StatelessWidget 이었을 때는 controller 없이 RawScrollbar 가 PrimaryScrollController
  // 로 fallback -> Windows 에서 자동 attach 안 됨 -> "Scrollbar's ScrollController
  // has no ScrollPosition attached" 에러 발생. 명시적 controller 로 회피.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  OrderModel get order => widget.order;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final hasNickname = order.userName != null && order.userName!.isNotEmpty;
    final paymentLabel = _paymentLabel(t, order.paymentType);
    final discountLabel = _discountLabel(t, order.discountTypes);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasNickname) ...[
            Text(
              t.order.customer_honorific(name: order.userName!),
              style: AppTextStyles.titleSm,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          _InfoRow(
            icon: Icons.schedule,
            label: t.order.ordered_time_short(
              time: DateFormat('HH:mm').format(order.orderedAt),
            ),
          ),
          if (paymentLabel != null) ...[
            const SizedBox(height: AppSpacing.s8),
            _InfoRow(
              icon: Icons.credit_card,
              label: paymentLabel,
            ),
          ],
          if (discountLabel != null) ...[
            const SizedBox(height: AppSpacing.s8),
            _InfoRow(
              icon: Icons.local_offer,
              label: discountLabel,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s16),
            child: Divider(height: 1, color: AppStyles.gray2),
          ),
          Text(
            t.order.memo,
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
          const SizedBox(height: AppSpacing.s8),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 100,
                maxHeight: 240,
              ),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppStyles.gray1,
                  borderRadius: AppRadius.bSm,
                ),
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Builder(builder: (context) {
                  final scrollView = SingleChildScrollView(
                    controller: _scrollController,
                    child: Text(
                      _editNote(order.note),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppStyles.gray9,
                      ),
                    ),
                  );
                  // attach 안 된 첫 frame 은 RawScrollbar 없이 표시.
                  if (!_scrollController.hasClients) return scrollView;
                  return RawScrollbar(
                    thumbVisibility: true,
                    radius: const Radius.circular(AppRadius.sm),
                    thickness: AppSpacing.s4,
                    controller: _scrollController,
                    child: scrollView,
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _editNote(String? note) {
    if (note == null) return '';
    return note.replaceAll('\\n', ' ');
  }

  // paymentType 코드를 i18n 라벨로 매핑. FREE / 빈 값은 null 반환하여 정보 카드에서
  // 행 자체를 숨김 (FREE 는 쿠폰/포인트로 100% 할인된 케이스 -> 할인 행에서 이미 노출).
  String? _paymentLabel(Translations t, String paymentType) {
    switch (paymentType.toUpperCase()) {
      case 'CREDIT_CARD':
      case 'CARD':
        return t.order.payment_method.credit_card;
      case 'PREPAID_CARD':
        return t.order.payment_method.prepaid_card;
      case 'NAVER_PAY':
        return t.order.payment_method.naver_pay;
      case 'KAKAO_PAY':
        return t.order.payment_method.kakao_pay;
      case 'TOSS_PAY':
        return t.order.payment_method.toss_pay;
      case 'APPLE_PAY':
        return t.order.payment_method.apple_pay;
      case 'PAYCO':
        return t.order.payment_method.payco;
      case 'EASY_CARD':
        return t.order.payment_method.easy_card;
      case 'MOBILE_PAYMENT':
        return t.order.payment_method.mobile_payment;
      case 'QR_PAYMENT':
        return t.order.payment_method.qr_payment;
      case 'FELICA_TRANSPORTATION':
        return t.order.payment_method.felica_transportation;
      case 'FELICA_ID':
        return t.order.payment_method.felica_id;
      case 'FELICA_QUICPAY':
        return t.order.payment_method.felica_quicpay;
      case 'CASH':
        return t.order.payment_method.cash;
      case 'SERVICE':
        return t.order.payment_method.service;
      case 'FREE':
      case '':
        return null;
      default:
        return paymentType;
    }
  }

  // orderDiscounts 의 distinct discountType 목록을 i18n 라벨 한 줄로 합침.
  // 비어 있으면 null -> 행 자체 숨김.
  String? _discountLabel(Translations t, List<String> types) {
    if (types.isEmpty) return null;
    String mapOne(String type) {
      switch (type.toUpperCase()) {
        case 'COUPON':
          return t.order.discount_type.coupon;
        case 'POINT':
          return t.order.discount_type.point;
        case 'GIFT':
          return t.order.discount_type.gift;
        case 'PARTNER':
          return t.order.discount_type.partner;
        case 'MEMBERSHIP':
          return t.order.discount_type.membership;
        default:
          return type;
      }
    }

    return types.map(mapOne).join(', ');
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppStyles.gray6),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray9),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
