import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';
import '../../constants/card_types.dart';
import '../../models/order_model.dart';
import '../../providers/kds_unified_providers.dart';
import '../../utils/logger.dart';
import '../../services/platform_service.dart';
import '../../widgets/common/common_dialog.dart';
import '../../providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../i18n/strings.g.dart';
import '../../exceptions/api_exceptions.dart';

// 공통 버튼 스타일
class KdsButtonStyle {
  static ButtonStyle get primary => ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppStyles.kMainColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
      );

  static ButtonStyle get secondary => ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppStyles.gray2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
      );
}

// 진행 탭용 하단 버튼 위젯
class KdsProgressBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsProgressBottomButtonsWidget({
    Key? key,
    required this.order,
    this.onOrderDetailTap,
  }) : super(key: key);

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
            child: ElevatedButton(
              onPressed: () async {
                // await 전에 캡처 (다이얼로그 대기 중 위젯 dispose 대비)
                final animationsNotifier = ref.read(kdsCardAnimationsProvider.notifier);
                final orderNotifier = ref.read(orderProvider.notifier);
                final navigator = Navigator.of(context);

                final isPickup = await CommonDialog.showConfirmDialog(
                  context: context,
                  title: t.kds.btn_pickup_request,
                  content: t.kds.msg_pickup_confirm(n: order.displayNum),
                  confirmText: t.common.confirm,
                  cancelText: t.common.cancel,
                );
                if (isPickup == true) {
                  logToFile(
                      tag: LogTag.UI_ACTION,
                      message:
                          'KDS 카드 픽업 요청: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                  try {
                    // 1단계: 애니메이션 먼저 시작
                    animationsNotifier.startStatusChangeAnimation(order.orderId);

                    // 2단계: 약간의 지연 후 상태 변경 (애니메이션이 보이도록)
                    await Future.delayed(const Duration(milliseconds: 300));

                    // 3단계: 실제 상태 변경
                    final success = await orderNotifier.updateOrderStatus(order, OrderStatus.READY);
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
                        );
                      }
                    }
                  } catch (e, s) {
                    logToFile(
                        tag: LogTag.UI_ACTION,
                        message:
                            'KDS 픽업 요청 오류: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}, error=$e');
                    logger.e('KDS: 픽업 처리 오류 - ${e.runtimeType}: $e', error: e, stackTrace: s);
                    if (navigator.mounted) {
                      CommonDialog.showInfoDialog(
                        context: navigator.context,
                        title: t.common.error_title,
                        content: e is ApiException ? e.message : t.order_detail.status_update_fail,
                      );
                    }
                  }
                }
              },
              style: KdsButtonStyle.primary,
              child: Text(
                t.kds.btn_pickup_request,
                style: const TextStyle(
                  color: Colors.white,
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

// 픽업 탭용 하단 버튼 위젯
class KdsPickupBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsPickupBottomButtonsWidget({
    Key? key,
    required this.order,
    this.onOrderDetailTap,
  }) : super(key: key);

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
            child: ElevatedButton(
              onPressed: () async {
                final isDone = await CommonDialog.showConfirmDialog(
                  context: context,
                  title: t.kds.btn_order_complete,
                  content: t.order_detail.dialog_complete_confirm_content(
                      n: order.displayNum), // "주문을 완료 처리하시겠습니까?" 와 유사한 문구 사용
                  confirmText: t.common.confirm,
                  cancelText: t.common.cancel,
                );
                if (isDone == true) {
                  final navigator = Navigator.of(context);
                  logToFile(
                      tag: LogTag.UI_ACTION,
                      message:
                          'KDS 카드 완료 처리: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}');
                  try {
                    // 애니메이션 시작
                    ref
                        .read(kdsCardAnimationsProvider.notifier)
                        .startStatusChangeAnimation(order.orderId);

                    // 지연 후 상태 변경
                    await Future.delayed(const Duration(milliseconds: 300));

                    // 실제 상태 변경 (READY -> DONE)
                    final success = await ref.read(orderProvider.notifier).updateOrderStatus(
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
                        );
                      }
                    }
                  } catch (e, s) {
                    logToFile(
                        tag: LogTag.UI_ACTION,
                        message:
                            'KDS 완료 처리 오류: displayNum=${order.displayNum}, simpleNum=${order.shopOrderNo}, orderId=${order.orderId}, error=$e');
                    logger.e('KDS: 완료 처리 오류 - ${e.runtimeType}: $e', error: e, stackTrace: s);
                    if (navigator.mounted) {
                      CommonDialog.showInfoDialog(
                        context: navigator.context,
                        title: t.common.error_title,
                        content: e is ApiException ? e.message : t.order_detail.status_update_fail,
                      );
                    }
                  }
                }
              },
              style: KdsButtonStyle.primary,
              child: Text(
                t.kds.btn_order_complete,
                style: const TextStyle(
                  color: Colors.white,
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

// 완료 탭용 하단 버튼 위젯
class KdsCompletedBottomButtonsWidget extends ConsumerWidget {
  final OrderModel order;
  final VoidCallback? onOrderDetailTap;

  const KdsCompletedBottomButtonsWidget({
    Key? key,
    required this.order,
    this.onOrderDetailTap,
  }) : super(key: key);

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
    Key? key,
    required this.order,
    this.onOrderDetailTap,
  }) : super(key: key);

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
    Key? key,
    required this.order,
    required this.cardType,
    this.onOrderDetailTap,
  }) : super(key: key);

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
