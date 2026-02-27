import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../models/order_model.dart';
import '../../providers/order_provider.dart';
import 'order_card_widget.dart';
import '../../widgets/common/common_dialog.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
import 'package:kokonut_order_agent/i18n/strings.g.dart';

// ConsumerStatefulWidget으로 변경
class OrderSectionWidget extends ConsumerStatefulWidget {
  final String title;
  final List<OrderModel> orders;
  final Color color;
  final OrderStatus status;
  final Function(OrderModel) onOrderTap;

  const OrderSectionWidget({
    Key? key,
    required this.title,
    required this.orders,
    required this.color,
    required this.status,
    required this.onOrderTap,
  }) : super(key: key);

  @override
  ConsumerState<OrderSectionWidget> createState() => _OrderSectionWidgetState();
}

// State 클래스 추가
class _OrderSectionWidgetState extends ConsumerState<OrderSectionWidget> {
  late final ScrollController _horizontalScrollController;
  bool _showScrollStartButton = false;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _horizontalScrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _horizontalScrollController.removeListener(_scrollListener);
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OrderSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 주문 목록이 비워졌을 때 스크롤 버튼 상태 초기화
    if (widget.orders.isEmpty && oldWidget.orders.isNotEmpty) {
      if (_showScrollStartButton) {
        setState(() {
          _showScrollStartButton = false;
        });
      }
    }
  }

  void _scrollListener() {
    if (!mounted) return; // 위젯이 마운트되지 않았으면 리스너 실행 중지
    // 스크롤 위치가 100 이상이고 버튼이 안 보이면 보이게 함
    if (_horizontalScrollController.offset >= 100 && !_showScrollStartButton) {
      setState(() {
        _showScrollStartButton = true;
      });
      // 스크롤 위치가 100 미만이고 버튼이 보이면 숨김
    } else if (_horizontalScrollController.offset < 100 &&
        _showScrollStartButton) {
      setState(() {
        _showScrollStartButton = false;
      });
    }
  }

  void _scrollToStart() {
    _horizontalScrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isAcceptedSection = widget.status == OrderStatus.PREPARING;
    bool isReadyForPickupSection = widget.status == OrderStatus.READY;
    bool checkReady = isReadyForPickupSection && widget.orders.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey[400]!,
          ),
        ),
      ),
      child: Row(
        children: [
          // 섹션 헤더
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 120,
              height: MediaQuery.of(context).size.height,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppStyles.kSectionTitleSize,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: checkReady
                          ? () async {
                              // 스낵바 대신 다이얼로그 표시
                              final confirm =
                                  await CommonDialog.showConfirmDialog(
                                context: context,
                                title:
                                    t.order_status.batch_complete_confirm_title,
                                content: t.order_status
                                    .batch_complete_confirm_content(
                                        n: widget.orders.length),
                                confirmText: t.common.confirm,
                                cancelText: t.common.cancel,
                              );

                              // 사용자가 '확인'을 눌렀을 경우
                              if (confirm == true) {
                                logger
                                    .i('일괄 완료 처리 시작: ${widget.orders.length}건');
                                final int totalCount = widget.orders.length;
                                String resultMessage = '';
                                try {
                                  // Order Provider의 메서드 호출하고 결과 직접 받기
                                  final result = await ref
                                      .read(orderProvider.notifier)
                                      .completeReadyOrders();

                                  // 반환된 결과로 메시지 구성
                                  if (result.errorMessage != null) {
                                    if (result.successCount > 0) {
                                      // 일부 성공, 일부 실패
                                      resultMessage = t.order_status
                                          .batch_result_partial(
                                              success: result.successCount,
                                              fail: result.failCount);
                                    } else {
                                      // 전체 실패
                                      resultMessage = t.order_status
                                          .batch_result_fail(
                                              error: result.errorMessage ?? '');
                                    }
                                  } else {
                                    // 전체 성공
                                    resultMessage = t.order_status
                                        .batch_result_success(n: totalCount);
                                  }
                                } catch (e, s) {
                                  logger.e('일괄 완료 처리 UI 오류',
                                      error: e, stackTrace: s);
                                  resultMessage =
                                      t.order_status.batch_result_error;
                                }

                                // 결과 다이얼로그 표시 (SnackBar 제거)
                                if (context.mounted) {
                                  CommonDialog.showInfoDialog(
                                    context: context,
                                    title: t.order_status.batch_result_title,
                                    content: resultMessage,
                                  );
                                }
                              }
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: checkReady
                                ? Border.all(color: AppStyles.kMainColor)
                                : null),
                        child: Text(
                          t.order_status.order_count(n: widget.orders.length),
                          style: const TextStyle(
                            fontSize: AppStyles.kSectionCountSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 주문 카드 목록 (Stack으로 감싸기)
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft, // 버튼을 왼쪽에 정렬
              children: [
                ListView.builder(
                  controller: _horizontalScrollController, // 컨트롤러 연결
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  itemCount: widget.orders.length,
                  itemBuilder: (context, index) {
                    const double cardSize = 100.0;
                    return SizedBox(
                      height: cardSize,
                      child: OrderCardWidget(
                        order: widget.orders[index],
                        onTap: () {
                          ref.read(orderProvider.notifier).stopBlinking();
                          widget.onOrderTap(widget.orders[index]);
                        },
                      ),
                    );
                  },
                ),
                // "맨 앞으로" 버튼
                if (_showScrollStartButton && widget.orders.isNotEmpty)
                  Positioned(
                    left: 0,
                    child: FloatingActionButton.small(
                      // small 사이즈 사용
                      onPressed: _scrollToStart,
                      backgroundColor:
                          AppStyles.kMainColor.withValues(alpha: 0.7),
                      tooltip: t.order_status.scroll_to_start,
                      heroTag: null,
                      child: const Icon(
                        Icons.first_page,
                        color: Colors.white,
                      ), // 여러 버튼 사용 시 고유 태그 필요 방지
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
