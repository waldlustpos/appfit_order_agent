import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/utils/payment_label_util.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 주문 상세 팝업 가운데 카드 — **돈에 관한 모든 정보**를 한 카드에 모은다.
///
/// 구성: 주문금액 / 할인금액(+종류별 상세) / 결제금액 / 결제수단별 사용액 /
/// 현금영수증 · 적립. 금액 숫자가 전부 같은 우측선에 정렬되도록 한 축으로 묶었다.
///
/// 결제수단·할인 상세는 [OrderModel] 의 상세 전용 필드라 목록 응답만 있는
/// 주문에서는 비어 있다. 그 경우 해당 섹션을 통째로 숨겨서, 기존과 동일한
/// 3줄 카드로 자연스럽게 축소된다.
class OrderPaymentInfoWidget extends StatefulWidget {
  final OrderModel order;
  final String currencySymbol;

  const OrderPaymentInfoWidget({
    super.key,
    required this.order,
    required this.currencySymbol,
  });

  @override
  State<OrderPaymentInfoWidget> createState() => _OrderPaymentInfoWidgetState();
}

class _OrderPaymentInfoWidgetState extends State<OrderPaymentInfoWidget> {
  /// 카드 본문 스크롤 + RawScrollbar attach 용 전용 controller.
  /// controller 없이 RawScrollbar 를 쓰면 PrimaryScrollController 로 fallback 되어
  /// Windows 에서 "Scrollbar's ScrollController has no ScrollPosition attached"
  /// 로 터진다 (order_info_panel_widget.dart 와 동일한 이유).
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  OrderModel get order => widget.order;

  String _price(double amount) =>
      CommonUtil.formatPrice(amount, currencyUnit: widget.currencySymbol);

  /// 표시 대상 결제수단. **0원 건은 뺀다** — 100% 쿠폰/포인트로 결제액이 0 이 된
  /// 경우 서버가 `FREE 0원` 건을 실어 보내는데, 그 사실은 바로 위 할인 상세에서
  /// 이미 드러나므로 '무료 0원' 줄은 정보 없는 중복이다.
  List<OrderPaymentModel> get _visiblePayments =>
      order.payments.where((p) => p.amount != 0).toList();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final payments = _visiblePayments;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(t.order.amount, _price(order.totalAmount),
            style: AppTextStyles.body),
        const SizedBox(height: AppSpacing.s12),
        _buildRow(t.order.discount, '-${_price(order.discountAmount)}',
            style: AppTextStyles.body.copyWith(color: AppStyles.gray6)),
        ...order.discounts.map((d) => _buildDiscountDetailRow(t, d)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
          child: Divider(height: 1, color: AppStyles.gray3),
        ),
        _buildRow(t.order.payment, _price(order.paymentAmount),
            style: AppTextStyles.titleSm.copyWith(color: AppStyles.kMainColor)),
        if (payments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s20),
          _buildSectionHeader(
            t.order.payment_breakdown,
            trailing: payments.length > 1
                ? t.order.payment_count(n: payments.length)
                : null,
          ),
          const SizedBox(height: AppSpacing.s8),
          ...payments.map((p) => _buildPaymentRow(t, p)),
        ],
      ],
    );

    final scrollView = SingleChildScrollView(
      controller: _scrollController,
      child: content,
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      padding: const EdgeInsets.all(AppSpacing.s20),
      // attach 안 된 첫 frame 은 RawScrollbar 없이 표시.
      child: !_scrollController.hasClients
          ? scrollView
          : RawScrollbar(
              thumbVisibility: true,
              radius: const Radius.circular(AppRadius.sm),
              thickness: AppSpacing.s4,
              controller: _scrollController,
              child: scrollView,
            ),
    );
  }

  /// 라벨 ↔ 금액 좌우 정렬 행. 금액 문자열은 호출자가 완성해서 넘긴다
  /// (할인은 `-` 접두가 붙기 때문).
  Widget _buildRow(String label, String amountText,
      {required TextStyle style}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Text(amountText, style: style),
      ],
    );
  }

  Widget _buildSectionHeader(String label, {String? trailing}) {
    return Row(
      children: [
        Text(
          label,
          style: AppTextStyles.bodySm
              .copyWith(color: AppStyles.gray6, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (trailing != null)
          Text(trailing,
              style: AppTextStyles.caption.copyWith(color: AppStyles.gray6)),
      ],
    );
  }

  /// 할인 1건. 종류(+쿠폰명)와 금액을 들여쓰기해서 상위 '할인금액' 행에 종속시킨다.
  Widget _buildDiscountDetailRow(Translations t, OrderDiscountModel d) {
    final type = discountTypeLabel(t, d.discountType);
    final label = (d.couponName != null && d.couponName!.isNotEmpty)
        ? '$type (${d.couponName})'
        : type;
    final style = AppTextStyles.bodySm.copyWith(color: AppStyles.gray6);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8, left: AppSpacing.s12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text('-${_price(d.discountAmount)}', style: style),
        ],
      ),
    );
  }

  /// 결제수단 1건 = 아이콘 · 수단명 · 금액 한 줄.
  ///
  /// 결제 상태(취소/실패/대기)는 표시하지 않는다. 주문이 취소면 결제도 취소라는
  /// 전제가 성립하고, 주문 상태는 팝업 헤더의 상태 배지가 이미 보여준다. 여기에
  /// 취소선·배지를 또 그리면 같은 사실을 두 번 말하면서 행만 시끄러워진다.
  /// 카드사·카드번호·할부 같은 카드 상세도 이 카드의 관심사가 아니라 뺐다
  /// (파싱은 계속 하므로 필요하면 상세 로그에서 확인할 수 있다).
  Widget _buildPaymentRow(Translations t, OrderPaymentModel p) {
    final style = AppTextStyles.bodySm.copyWith(color: AppStyles.gray9);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        children: [
          Icon(_iconFor(p.paymentMethod), size: 16, color: AppStyles.gray6),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              paymentMethodLabel(t, p.paymentMethod),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(_price(p.amount),
              style: style.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// 결제수단 아이콘. 전부 표준 MaterialIcons 라 추가 폰트가 필요 없다.
  /// 우측 정보 패널의 `Icon(size: 16, color: gray6)` 규격과 맞춰 카드 3장이
  /// 한 세트로 보이게 한다(이모지는 Windows/Android 폰트 차이가 커서 피했다).
  IconData _iconFor(String method) {
    switch (method.toUpperCase()) {
      case 'CREDIT_CARD':
      case 'CARD':
      case 'APP_CARD':
      case 'EASY_CARD':
        return Icons.credit_card;
      case 'PREPAID_CARD':
        return Icons.card_giftcard;
      case 'CASH':
        return Icons.payments_outlined;
      case 'GIFT':
        return Icons.redeem;
      case 'FREE':
      case 'SERVICE':
        return Icons.local_offer;
      case 'QR_PAYMENT':
        return Icons.qr_code_2;
      case 'FELICA_TRANSPORTATION':
      case 'FELICA_ID':
      case 'FELICA_QUICPAY':
        return Icons.contactless;
      case 'BANK_TRANSFER':
        return Icons.account_balance;
      case 'MULTI':
        return Icons.call_split;
      case 'NAVER_PAY':
      case 'KAKAO_PAY':
      case 'TOSS_PAY':
      case 'TOSS_PAY_DIRECT':
      case 'APPLE_PAY':
      case 'PAYCO':
      case 'KB_PAY':
      case 'HANA_PAY':
      case 'WOORI_PAY':
      case 'KARROT_PAY':
      case 'ZERO_PAY':
      case 'EASY_PAYMENT':
      case 'MOBILE_PAYMENT':
      case 'LOCAL_CURRENCY':
        return Icons.account_balance_wallet;
      default:
        return Icons.payment;
    }
  }
}
