import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

/// 가로 스크롤 컨테이너에 좌/우 화살표 오버레이를 제공하는 위젯.
///
/// [controller]의 스크롤 위치를 감시해 스크롤 가능 방향에만 화살표를 표시한다.
/// 호출자의 [Stack] 안에 배치하여 사용한다:
/// ```dart
/// Stack(children: [
///   ListView.builder(...),
///   HorizontalScrollArrowOverlay(
///     controller: _scrollController,
///     listVersion: orders.length,
///   ),
/// ])
/// ```
///
/// [listVersion]이 변경되면 아이템 수 변경 후 maxScrollExtent가 재계산된 뒤
/// 화살표 상태를 postFrameCallback으로 재평가한다.
/// (우측 끝 고정 상태에서 신규 주문 추가 시 화살표 미갱신 버그 대응)
class HorizontalScrollArrowOverlay extends StatefulWidget {
  const HorizontalScrollArrowOverlay({
    super.key,
    required this.controller,
    required this.listVersion,
    this.tooltipStart,
    this.tooltipEnd,
    this.arrowSize = 44,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  final ScrollController controller;

  /// 아이템 수 등 외부 변화를 알리는 버전 값.
  /// 변경 시 postFrameCallback으로 화살표 상태를 재평가한다.
  final int listVersion;

  final String? tooltipStart;
  final String? tooltipEnd;
  final double arrowSize;
  final Duration animationDuration;

  @override
  State<HorizontalScrollArrowOverlay> createState() =>
      _HorizontalScrollArrowOverlayState();
}

class _HorizontalScrollArrowOverlayState
    extends State<HorizontalScrollArrowOverlay> {
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
  }

  @override
  void didUpdateWidget(HorizontalScrollArrowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _update();
      });
    }
    // 아이템 수 변경 시 maxScrollExtent 재계산 후 화살표 재평가
    if (oldWidget.listVersion != widget.listVersion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _update();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    final maxExtent = widget.controller.position.maxScrollExtent;
    final newLeft = offset > 5.0;
    final newRight = offset < maxExtent - 5.0;
    if (newLeft != _canScrollLeft || newRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = newLeft;
        _canScrollRight = newRight;
      });
    }
  }

  void _scrollTo(bool isLeft) {
    if (!widget.controller.hasClients) return;
    widget.controller.animateTo(
      isLeft ? 0.0 : widget.controller.position.maxScrollExtent,
      duration: widget.animationDuration,
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_canScrollLeft)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _ArrowButton(
              isLeft: true,
              arrowSize: widget.arrowSize,
              tooltip: widget.tooltipStart,
              onTap: () => _scrollTo(true),
            ),
          ),
        if (_canScrollRight)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _ArrowButton(
              isLeft: false,
              arrowSize: widget.arrowSize,
              tooltip: widget.tooltipEnd,
              onTap: () => _scrollTo(false),
            ),
          ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.isLeft,
    required this.arrowSize,
    required this.onTap,
    this.tooltip,
  });

  final bool isLeft;
  final double arrowSize;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final gradientWidth = arrowSize + 4;
    return Container(
      width: gradientWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Center(
        child: Tooltip(
          message: tooltip ?? '',
          child: Container(
            width: arrowSize,
            height: arrowSize,
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
                onTap: onTap,
                child: Center(
                  child: Icon(
                    isLeft
                        ? Icons.arrow_back_ios_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 22,
                    color: AppStyles.gray9,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
