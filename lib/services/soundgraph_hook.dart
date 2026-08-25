import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/soundgraph_service.dart';

/// 주문 접수(자동·수동 공통) 성공 직후 발화하는 주문 라이프사이클 외부 통합 hook.
///
/// 게이팅(어느 브랜드가 외부 통합을 쓰는지)은 [soundGraphHookProvider] 가
/// capability([BrandFeature.soundGraphSend])로 결정한다. hook 자체는
/// "접수된 주문으로 무엇을 하는가"라는 동작만 담는다.
abstract class SoundGraphHook {
  const SoundGraphHook();

  /// 주문이 접수(PREPARING)된 직후 호출된다 — 자동접수·수동접수 공통 단일
  /// 진입점(updateOrderStatus)에서 발화하므로 호출부가 어느 쪽인지는 구분하지
  /// 않는다. 실패해도 주문 처리를 막지 않는다.
  void onAccepted(OrderModel order);
}

/// 아무것도 하지 않는 기본 hook (사운드그래프 미지원 브랜드).
class NoOpSoundGraphHook extends SoundGraphHook {
  const NoOpSoundGraphHook();

  @override
  void onAccepted(OrderModel order) {}
}

/// 매머드(MMTH 운영/MHST 스테이징) 전용 사운드그래프 주문 전송 hook.
///
/// 토글(getSoundGraphOn) + marketId 검증 후 [SoundGraphService] 로 외부 전송.
/// brandId('mmth')는 매머드 브랜드 식별자이며 본 hook 이 모델에 주입한다(모델은 브랜드 무관).
class MhstSoundGraphHook extends SoundGraphHook {
  MhstSoundGraphHook({required this.service, this.brandId = 'mmth'});

  final SoundGraphService service;
  final String brandId;

  @override
  void onAccepted(OrderModel order) {
    final prefs = PreferenceService();
    if (!prefs.getSoundGraphOn()) return;
    final marketId = prefs.getSoundGraphMarketId();
    if (marketId.isEmpty) {
      logToFile(
        tag: LogTag.SOUNDGRAPH,
        message:
            '[SoundGraph] enabled but marketId empty, skip ${order.orderNo}',
      );
      return;
    }
    if (order.menus.isEmpty) {
      logToFile(
        tag: LogTag.SOUNDGRAPH,
        message: '[SoundGraph] menus empty, skip ${order.orderNo}',
      );
      return;
    }
    final payload = order.toJsonForSoundGraph(marketId, brandId: brandId);
    logToFile(
      tag: LogTag.SOUNDGRAPH,
      message: '[SoundGraph] sending ${order.orderNo} payload: $payload',
    );
    service.sendOrder(payload).then((ok) {
      logToFile(
        tag: LogTag.SOUNDGRAPH,
        message: ok
            ? '[SoundGraph] send OK ${order.orderNo}'
            : '[SoundGraph] send FAIL ${order.orderNo}',
      );
    }).catchError((e, s) {
      logger.e('[SoundGraph] sendOrder error ${order.orderNo}',
          error: e, stackTrace: s);
    });
  }
}

/// 현재 브랜드에 맞는 [SoundGraphHook] 을 제공한다.
///
/// capability [BrandFeature.soundGraphSend] 를 가진 브랜드만
/// [MhstSoundGraphHook], 그 외는 [NoOpSoundGraphHook]. 이로써 TPCP/MATA 매장이
/// 토글을 켜도 외부 전송이 발생하지 않는다(크로스-브랜드 누수 차단).
final soundGraphHookProvider = Provider<SoundGraphHook>((ref) {
  final brand = ref.watch(currentBrandProvider);
  if (!(brand?.has(BrandFeature.soundGraphSend) ?? false)) {
    return const NoOpSoundGraphHook();
  }
  return MhstSoundGraphHook(service: ref.read(soundGraphServiceProvider));
});
