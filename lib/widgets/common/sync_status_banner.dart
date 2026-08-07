import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/api_health_provider.dart';
import 'package:appfit_order_agent/providers/order/order_provider.dart';

/// 서버 응답이 지연되고 있음을 주문 화면 상단에 알리는 띠.
///
/// 정상일 때는 [SizedBox.shrink] 라 레이아웃 비용이 0 이다.
///
/// **왜 앱바 아이콘으로 부족한가**: 앱바에는 이미 소켓/네트워크 상태 아이콘이
/// 있지만 24×24 다. 2026-08-07 장애에서 운영자는 14분 동안 그 아이콘을
/// 알아채지 못한 채 새로고침만 반복해서 눌렀다. 주방·카운터 화면은 원거리에서
/// 힐끗 보는 화면이라 상태 변화가 그만한 면적을 차지해야 인지된다.
///
/// KDS 모드와 일반 주문 모드 **양쪽**에 배치한다. 두 모드 모두 같은 HTTP
/// 파이프라인 위에서 돌고, 장애도 모드를 가리지 않는다.
///
/// 사라지는 통지(SnackBar·토스트)를 쓰지 않은 이유: 지연은 지속되는 조건이라
/// 아무도 보지 않는 사이에 떴다 사라지면 아무 일도 하지 않은 것과 같다.
class SyncStatusBanner extends ConsumerStatefulWidget {
  const SyncStatusBanner({super.key});

  @override
  ConsumerState<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends ConsumerState<SyncStatusBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await ref
          .read(orderProvider.notifier)
          .refreshOrders()
          .timeout(const Duration(seconds: 60), onTimeout: () {});
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// `intl` 을 끌어오지 않기 위한 최소 포맷. 배너에는 시:분이면 충분하다.
  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // isDegraded 와 lastSuccessAt 만 구독한다. 연속 실패 횟수가 1→2→3 으로
    // 오르는 동안 배너를 매번 다시 그릴 이유는 없다.
    final (isDegraded, lastSuccessAt) = ref.watch(
      apiHealthNotifierProvider.select((h) => (h.isDegraded, h.lastSuccessAt)),
    );
    if (!isDegraded) return const SizedBox.shrink();

    final lastText = lastSuccessAt == null
        ? t.common.sync.never_updated
        : t.common.sync.last_updated(time: _hhmm(lastSuccessAt));

    return Container(
      width: double.infinity,
      height: 44,
      color: AppStyles.kAmber,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.sync_problem, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.common.sync.degraded,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            lastText,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: TextButton(
              onPressed: _retrying ? null : _retry,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.bSm,
                  side: BorderSide(color: Colors.white70),
                ),
              ),
              child: _retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      t.common.sync.retry_now,
                      style: const TextStyle(fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
