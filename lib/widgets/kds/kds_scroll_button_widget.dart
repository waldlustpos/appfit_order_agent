import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../providers/kds_unified_providers.dart';
import '../../providers/providers.dart';

// 상단 스크롤 버튼 위젯
class KdsScrollUpButtonWidget extends ConsumerWidget {
  final String orderId;
  final Map<String, ScrollController> scrollControllers;
  final Function(String) updateScrollButtonVisibility;

  const KdsScrollUpButtonWidget({
    Key? key,
    required this.orderId,
    required this.scrollControllers,
    required this.updateScrollButtonVisibility,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canScrollUp =
        ref.watch(kdsScrollButtonStatesProvider)[orderId]?.canScrollUp ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.white.withValues(alpha: 0.3),
            Colors.white,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(color: AppStyles.gray4),
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canScrollUp
                    ? () {
                        final controller = scrollControllers[orderId];
                        if (controller != null && controller.hasClients) {
                          // 부드러운 애니메이션으로 맨 위로 스크롤
                          controller
                              .animateTo(
                            0.0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                              .then((_) {
                            // 애니메이션 완료 후 스크롤 위치 저장
                            ref
                                .read(kdsScrollPositionsProvider.notifier)
                                .saveScrollPosition(orderId, 0.0);

                            // 스크롤 버튼 가시성 업데이트
                            updateScrollButtonVisibility(orderId);
                          });
                        }
                      }
                    : null,
                child: Center(
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: canScrollUp ? AppStyles.gray9 : AppStyles.gray4,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// 하단 스크롤 버튼 위젯
class KdsScrollDownButtonWidget extends ConsumerWidget {
  final String orderId;
  final Map<String, ScrollController> scrollControllers;
  final Function(String) updateScrollButtonVisibility;

  const KdsScrollDownButtonWidget({
    Key? key,
    required this.orderId,
    required this.scrollControllers,
    required this.updateScrollButtonVisibility,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canScrollDown =
        ref.watch(kdsScrollButtonStatesProvider)[orderId]?.canScrollDown ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.3),
            Colors.white,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(color: AppStyles.gray4),
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canScrollDown
                    ? () {
                        final controller = scrollControllers[orderId];
                        if (controller != null && controller.hasClients) {
                          // 부드러운 애니메이션으로 맨 아래로 스크롤
                          final maxExtent = controller.position.maxScrollExtent;
                          controller
                              .animateTo(
                            maxExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                              .then((_) {
                            // 애니메이션 완료 후 스크롤 위치 저장
                            ref
                                .read(kdsScrollPositionsProvider.notifier)
                                .saveScrollPosition(orderId, maxExtent);

                            // 스크롤 버튼 가시성 업데이트
                            updateScrollButtonVisibility(orderId);
                          });
                        }
                      }
                    : null,
                child: Center(
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 20,
                    color: canScrollDown ? AppStyles.gray9 : AppStyles.gray4,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
