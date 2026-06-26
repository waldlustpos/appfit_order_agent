import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:appfit_order_agent/config/app_env.dart';
import 'package:appfit_order_agent/services/windows_bubble_service.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 버블 모드 루트 위젯.
///
/// Android 벡터 드로어블(`ic_order_on.xml` / `ic_order_off.xml`)을 SVG로
/// 이식한 `assets/images/bubble_on.svg` / `bubble_off.svg`를 500ms 주기로
/// 교대 렌더링한다. 드래그는 [windowManager.startDragging], 클릭은
/// [WindowsBubbleService.exitBubbleMode]로 매핑된다.
///
/// standalone 변형에서는 "주문 있음"(on) 배경을 런처 아이콘과 동일한 대각선
/// 그라데이션(`bubble_on_standalone.svg`)으로 통일한다. off 상태는 깜빡임
/// 대비를 위해 두 변형 모두 흰색을 공용한다.
class WindowsBubbleOverlay extends StatelessWidget {
  const WindowsBubbleOverlay({super.key});

  /// "주문 있음"(on) 상태 버블 SVG 경로. standalone 은 그라데이션 배경.
  static const String _onAsset = AppEnv.isStandalone
      ? 'assets/images/bubble_on_standalone.svg'
      : 'assets/images/bubble_on.svg';

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
                  on ? _onAsset : 'assets/images/bubble_off.svg',
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
