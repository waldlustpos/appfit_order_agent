import 'package:flutter/material.dart';

import 'package:appfit_order_agent/dev/net_fault_injector.dart';

/// 네트워크 장애 주입이 무장돼 있음을 화면 최상단에 알리는 리본 (개발 전용).
///
/// 두 가지 역할을 한다:
/// - **오독 방지** — 합성 장애로 배너·실패 다이얼로그가 뜨는 동안, 그것이
///   주입 때문임을 화면에서 즉시 알 수 있어야 한다. 진짜 UI 로 오인할 수
///   없도록 새빨간 스트립을 쓴다.
/// - **패닉 해제** — 목록 조회를 죽여 화면이 빈 상태에서는 설정 화면까지
///   걸어가기가 번거롭다. 리본 탭 한 번으로 즉시 해제한다.
///
/// [kAllowFaultInjection] 이 `const` 라 릴리즈 빌드에서는
/// build 본문이 `SizedBox.shrink` 한 줄로 접힌다.
class FaultInjectionRibbon extends StatelessWidget {
  const FaultInjectionRibbon({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kAllowFaultInjection) return const SizedBox.shrink();

    return ValueListenableBuilder<NetFaultConfig>(
      valueListenable: NetFaultInjector.state,
      builder: (context, cfg, _) {
        if (!cfg.isActive) return const SizedBox.shrink();

        final targets = cfg.targets.map(_targetName).join('·');
        return Material(
          color: Colors.red.shade700,
          child: InkWell(
            onTap: NetFaultInjector.clear,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '장애 주입 무장중: $targets / ${cfg.kind.name} / '
                      '${cfg.delay.inSeconds}초 / 잔여 ${cfg.remaining ?? "∞"} '
                      '— 탭하여 해제 (10분 후 자동해제, 진행 중인 지연은 완주)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _targetName(NetFaultTarget t) => switch (t) {
        NetFaultTarget.orders => '목록',
        NetFaultTarget.orderDetail => '상세',
        NetFaultTarget.orderUpdate => '상태변경',
      };
}
