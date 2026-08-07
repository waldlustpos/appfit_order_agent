import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/card_types.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/widgets/kds/kds_async_button.dart';
import 'package:appfit_order_agent/providers/order/status_update_in_flight_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';

// 공통 버튼 스타일 — AppStyles 팩토리로 위임
class KdsButtonStyle {
  static ButtonStyle get primary => AppStyles.kdsCardPrimaryButton();
  static ButtonStyle get secondary => AppStyles.kdsCardSecondaryButton();
}

// 진행 탭용 하단 버튼 위젯
class KdsProgressBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsProgressBottomButtonsWidget({
    super.key,
    required this.order,
    this.onOrderDetailTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4, left: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: onOrderDetailTap,
              style: KdsButtonStyle.secondary,
              child: Text(
                t.kds.btn_detail,
                style: TextStyle(
                  color: AppStyles.gray6,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: KdsAsyncButton(
              text: t.kds.btn_pickup_request,
              style: KdsButtonStyle.primary,
              // 카드 서브트리가 조건부 교체되면 버튼 State 가 재생성돼 로컬 busy 가
              // 리셋된다(2026-08-08 실기기에서 재탭 관통으로 드러남). provider 를
              // 진실로 삼아 State 수명과 무관하게 잠근다.
              externalBusy: ref.watch(statusUpdateInFlightProvider
                  .select((s) => s.contains(order.orderId))),
              onPressed: () async {
                // await 전에 캡처 (다이얼로그 대기 중 위젯 dispose 대비)
                final orderNotifier = ref.read(orderProvider.notifier);
                final navigator = Navigator.of(context);

                final isPickup = await CommonDialog.showConfirmDialog(
                  context: context,
                  title: t.kds.btn_pickup_request,
                  content: t.kds.msg_pickup_confirm(n: order.displayNum),
                  confirmText: t.common.confirm,
                  cancelText: t.common.cancel,
                );
                if (isPickup != true) return;

                logToFile(
                    tag: LogTag.UI_ACTION,
                    message:
                        'KDS 카드 픽업 요청: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                try {
                  // 애니메이션은 여기서 켜지 않는다. 상태가 실제로 바뀌면
                  // kds_order_tracking_provider 가 도착 탭 카드에 걸어준다.
                  // 예전에는 API 호출 **전에** 미리 켜고 300ms 대기해서,
                  // (1) 실패해도 성공한 것처럼 보였고 (2) 곧 사라질 진행 탭
                  // 카드를 하이라이트하고 있었다. 진행 표시는 버튼 스피너 담당.
                  final success = await orderNotifier.updateOrderStatus(
                      order, OrderStatus.READY);
                  if (success) {
                    logToFile(
                        tag: LogTag.UI_ACTION,
                        message:
                            'KDS 픽업 요청 성공: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                  } else {
                    logToFile(
                        tag: LogTag.UI_ACTION,
                        message:
                            'KDS 픽업 요청 실패: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                    if (navigator.mounted) {
                      CommonDialog.showInfoDialog(
                        context: navigator.context,
                        title: t.common.error_title,
                        content: t.order_detail.status_update_fail,
                        // 주문별로 분리한다. 기본 dedupe 키는 title+content 라
                        // 여러 건이 동시에 실패하면 두 번째부터 조용히 삼켜졌다.
                        dedupeKey: 'status_fail_${order.orderId}',
                      );
                    }
                  }
                } on StateError catch (_) {
                  // 위젯 dispose 후 도달한 경우 무시 (Sentry 스팸 방지)
                } catch (e, s) {
                  logToFile(
                      tag: LogTag.UI_ACTION,
                      message:
                          'KDS 픽업 요청 오류: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}, error=$e');
                  logger.e('KDS: 픽업 처리 오류 - ${e.runtimeType}: $e',
                      error: e, stackTrace: s);
                  if (navigator.mounted) {
                    CommonDialog.showInfoDialog(
                      context: navigator.context,
                      title: t.common.error_title,
                      content: e is ApiException
                          ? e.message
                          : t.order_detail.status_update_fail,
                      dedupeKey: 'status_fail_${order.orderId}',
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 픽업 탭용 하단 버튼 위젯
class KdsPickupBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsPickupBottomButtonsWidget({
    super.key,
    required this.order,
    this.onOrderDetailTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4, left: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: onOrderDetailTap,
              style: KdsButtonStyle.secondary,
              child: Text(
                t.kds.btn_detail,
                style: TextStyle(
                  color: AppStyles.gray6,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: KdsAsyncButton(
              text: t.kds.btn_order_complete,
              style: KdsButtonStyle.primary,
              // 픽업 요청 쪽 주석 참조 — 같은 관통 경로다.
              externalBusy: ref.watch(statusUpdateInFlightProvider
                  .select((s) => s.contains(order.orderId))),
              onPressed: () async {
                // await 전에 ref/navigator 캡처 (다이얼로그 대기 중 위젯 dispose 대비)
                // Sentry APPFIT-ORDER-AGENT-1A: `Bad state: Cannot use "ref" after
                // the widget was disposed.` 방지
                final orderNotifier = ref.read(orderProvider.notifier);
                final navigator = Navigator.of(context);

                final isDone = await CommonDialog.showConfirmDialog(
                  context: context,
                  title: t.kds.btn_order_complete,
                  content: t.order_detail
                      .dialog_complete_confirm_content(n: order.displayNum),
                  confirmText: t.common.confirm,
                  cancelText: t.common.cancel,
                );
                if (isDone != true) return;

                logToFile(
                    tag: LogTag.UI_ACTION,
                    message:
                        'KDS 카드 완료 처리: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                try {
                  // 애니메이션 사전 트리거 제거 — 픽업 요청 쪽 주석 참조.
                  final success = await orderNotifier.updateOrderStatus(
                    order,
                    OrderStatus.DONE,
                  );
                  if (success) {
                    logToFile(
                        tag: LogTag.UI_ACTION,
                        message:
                            'KDS 완료 처리 성공: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                  } else {
                    logToFile(
                        tag: LogTag.UI_ACTION,
                        message:
                            'KDS 완료 처리 실패: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                    if (navigator.mounted) {
                      CommonDialog.showInfoDialog(
                        context: navigator.context,
                        title: t.common.error_title,
                        content: t.order_detail.status_update_fail,
                        dedupeKey: 'status_fail_${order.orderId}',
                      );
                    }
                  }
                } on StateError catch (_) {
                  // 위젯 dispose 후 도달한 경우 무시 (Sentry 스팸 방지)
                } catch (e, s) {
                  logToFile(
                      tag: LogTag.UI_ACTION,
                      message:
                          'KDS 완료 처리 오류: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}, error=$e');
                  logger.e('KDS: 완료 처리 오류 - ${e.runtimeType}: $e',
                      error: e, stackTrace: s);
                  if (navigator.mounted) {
                    CommonDialog.showInfoDialog(
                      context: navigator.context,
                      title: t.common.error_title,
                      content: e is ApiException
                          ? e.message
                          : t.order_detail.status_update_fail,
                      dedupeKey: 'status_fail_${order.orderId}',
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 완료 탭용 하단 버튼 위젯
class KdsCompletedBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsCompletedBottomButtonsWidget({
    super.key,
    required this.order,
    this.onOrderDetailTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4, left: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: onOrderDetailTap,
              style: KdsButtonStyle.secondary,
              child: Text(
                t.kds.btn_detail,
                style: TextStyle(
                  color: AppStyles.gray6,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 취소 탭용 하단 버튼 위젯
class KdsCancelledBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsCancelledBottomButtonsWidget({
    super.key,
    required this.order,
    this.onOrderDetailTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4, left: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: onOrderDetailTap,
              style: KdsButtonStyle.secondary,
              child: Text(
                t.kds.btn_detail,
                style: TextStyle(
                  color: AppStyles.gray6,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 타입3 카드용 특별한 레이아웃 버튼 위젯
class KdsType3BottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final CardType cardType;
  final VoidCallback? onOrderDetailTap;

  const KdsType3BottomButtonsWidget({
    super.key,
    required this.order,
    required this.cardType,
    this.onOrderDetailTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget buttonWidget;

    switch (cardType) {
      case CardType.progress:
        buttonWidget = KdsProgressBottomButtonsWidget(
          order: order,
          onOrderDetailTap: onOrderDetailTap,
        );
        break;
      case CardType.pickup:
        buttonWidget = KdsPickupBottomButtonsWidget(
          order: order,
          onOrderDetailTap: onOrderDetailTap,
        );
        break;
      case CardType.completed:
        buttonWidget = KdsCompletedBottomButtonsWidget(
          order: order,
          onOrderDetailTap: onOrderDetailTap,
        );
        break;
      case CardType.cancelled:
        buttonWidget = KdsCancelledBottomButtonsWidget(
          order: order,
          onOrderDetailTap: onOrderDetailTap,
        );
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Spacer(),
        SizedBox(width: 240, child: buttonWidget),
      ],
    );
  }
}
