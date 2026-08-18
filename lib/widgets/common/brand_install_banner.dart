import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';

/// 설치된 아티팩트와 매장 브랜드가 어긋났을 때 주문 화면 상단에 띄우는 안내 띠.
///
/// 일치할 때는 [SizedBox.shrink] 라 레이아웃 비용이 0 이다.
///
/// **왜 차단이 아니라 안내인가**: 브랜드 동작은 전부 런타임(`BrandRegistry`)이라
/// 어느 조합이든 주문·출력은 정상이다. 어긋남의 실제 증상은 "런처 아이콘·이름이
/// 브랜드와 다르다"뿐이므로, 매장을 멈춰 세울 이유가 없다. 대신 현장에서
/// 눈치채지 못한 채 몇 달을 쓰는 상황을 막는 것이 목적이다.
///
/// [SyncStatusBanner] 와 같은 자리·같은 규격이지만 **성격이 다르다** — 저쪽은
/// 저절로 해소되는 일시 상태고, 이쪽은 사람이 앱을 교체해야만 사라지는 설치
/// 조건이다. 그래서 재시도 버튼이 없다.
class BrandInstallBanner extends ConsumerWidget {
  const BrandInstallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mismatch = ref.watch(brandInstallMismatchProvider);
    if (mismatch == BrandInstallMismatch.none) return const SizedBox.shrink();

    final needsDedicated = mismatch == BrandInstallMismatch.needsDedicatedApp;
    final message = needsDedicated
        ? t.common.brand_install.needs_dedicated
        : t.common.brand_install.wrong_dedicated;

    return Container(
      width: double.infinity,
      height: 44,
      // 전용 앱 안내는 정보성(파랑), 잘못 깔린 단말은 경고성(앰버).
      color: needsDedicated ? AppStyles.kBlue : AppStyles.kAmber,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            needsDedicated ? Icons.info_outline : Icons.warning_amber_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
