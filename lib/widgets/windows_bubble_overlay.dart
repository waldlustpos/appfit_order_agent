import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:appfit_order_agent/services/windows_bubble_service.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 버블 모드 루트 위젯.
///
/// Android 벡터 드로어블(`ic_order_on.xml` / `ic_order_off.xml`)을 SVG로
/// 이식한 `assets/images/bubble_on.svg` / `bubble_off.svg`를 500ms 주기로
/// 교대 렌더링한다. 드래그는 [windowManager.startDragging], 클릭은
/// [WindowsBubbleService.exitBubbleMode]로 매핑된다.
class WindowsBubbleOverlay extends StatelessWidget {
  const WindowsBubbleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      // 창 크기 변화(80↔1440) 중에도 버블 크기가 부모 tight constraint를 따라
      // 확장/축소되지 않도록 Align+SizedBox로 80x80에 고정한다.
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 80,
          height: 80,
          child: StreamBuilder<bool>(
            stream: WindowsBubbleService.instance.blinkStream,
            initialData: true,
            builder: (context, snapshot) {
              final on = snapshot.data ?? true;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => WindowsBubbleService.instance.exitBubbleMode(),
                onPanStart: (_) => windowManager.startDragging(),
                child: SvgPicture.asset(
                  on
                      ? 'assets/images/bubble_on.svg'
                      : 'assets/images/bubble_off.svg',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
