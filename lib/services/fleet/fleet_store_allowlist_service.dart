import 'package:dio/dio.dart';

import 'package:appfit_order_agent/config/fleet_config.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

/// 원격 목록 1회 조회. 성공하면 디코딩된 JSON(Map 또는 List), 실패하면 null.
typedef FleetAllowlistFetcher = Future<Object?> Function();

/// 기기 관제(Fleet) **대상 매장** 판정.
///
/// 관제를 전 함대에 한꺼번에 켤 수는 없다 — 파일럿은 실기기 몇 대로 시작해야
/// 하고, 무료 티어 천장도 heartbeat 하루 10만회다. 그래서 빌드 타임 설정
/// ([AppEnv.hasFleetConfig]) 위에 **런타임 매장 화이트리스트**를 한 겹 얹는다.
/// 목록은 앱 밖(정적 호스트)에 있으므로 앱 재배포 없이 범위를 넓히거나 되돌릴 수 있다.
///
/// **조회 실패는 관제를 끄지 않는다.** 마지막으로 성공한 목록이 캐시에 남아
/// 있으면 그걸로 판정한다. 매장 인터넷이 잠깐 끊겼다고 파일럿 기기가 대시보드에서
/// 사라지면, 정작 관제가 필요한 상황에서 관제가 없어진다. 캐시조차 없을 때만
/// OFF(= 최초 설치 기기의 안전한 기본값).
class FleetStoreAllowlistService {
  FleetStoreAllowlistService(
    this._prefs, {
    FleetAllowlistFetcher? fetcher,
  }) : _fetch = fetcher ?? _defaultFetcher;

  final PreferenceService _prefs;
  final FleetAllowlistFetcher _fetch;

  /// 앱 Dio(`dioProvider`)를 쓰지 않는다 — baseUrl 이 AppFit API 서버로 고정돼
  /// 있고 인증/Project 헤더 인터셉터가 붙는다. 대상 호스트가 다르므로 별도
  /// 클라이언트를 쓰는 게 맞다(`slack_direct_sink.dart` 와 같은 논리).
  static Future<Object?> _defaultFetcher() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: FleetConfig.fetchConnectTimeout,
        receiveTimeout: FleetConfig.fetchReceiveTimeout,
      ),
    );
    try {
      final response = await dio.get<dynamic>(FleetConfig.storeAllowlistUrl);
      return response.data;
    } finally {
      dio.close(force: true);
    }
  }

  /// 원격 목록을 받아 캐시를 갱신한다. 성공 시 true.
  ///
  /// 실패하면 **캐시를 건드리지 않고** false 를 돌려준다. 빈 목록으로 성공한
  /// 경우는 "전부 OFF" 라는 정상 지시이므로 캐시를 빈 값으로 덮는다.
  Future<bool> refresh() async {
    try {
      final data = await _fetch();
      final codes = _parse(data);
      if (codes == null) {
        logToFile(
          tag: LogTag.FLEET,
          message: '대상 매장 목록 형식 불일치 — 캐시 유지',
        );
        return false;
      }
      await _prefs.setFleetStoreAllowlist(codes.join(','));
      logToFile(
        tag: LogTag.FLEET,
        message: '대상 매장 목록 갱신: ${codes.length}개',
      );
      return true;
    } catch (e) {
      // 404(목록 미업로드)·타임아웃·오프라인 모두 같은 처리. 관제 조회 실패가
      // 앱 동작에 영향을 주면 안 되므로 예외를 밖으로 내보내지 않는다.
      logToFile(
        tag: LogTag.FLEET,
        message: '대상 매장 목록 조회 실패 — 캐시로 판정 ($e)',
      );
      return false;
    }
  }

  /// 캐시된 목록으로 판정한다. 캐시가 없으면 false.
  bool isTargeted(String? storeId) {
    final normalized = storeId?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return false;
    final cached = _prefs.getFleetStoreAllowlist();
    if (cached == null) return false;
    return _split(cached).contains(normalized);
  }

  /// 진단용. 현재 캐시된 대상 매장 수(캐시 없음이면 null).
  int? get cachedCount {
    final cached = _prefs.getFleetStoreAllowlist();
    if (cached == null) return null;
    return _split(cached).length;
  }

  /// 응답을 매장 코드 집합으로. 형식이 어긋나면 null(= 캐시 유지 신호).
  ///
  /// 최상위가 Map 이면 `stores`, List 면 그 자체를 목록으로 본다. `stores` 가
  /// 없거나 비어 있는 것은 **오류가 아니라 "전부 OFF"** 다.
  static Set<String>? _parse(Object? data) {
    final List<Object?> raw;
    if (data is Map) {
      final stores = data['stores'];
      if (stores == null) return <String>{};
      if (stores is! List) return null;
      raw = stores;
    } else if (data is List) {
      raw = data;
    } else {
      return null;
    }

    return raw
        .whereType<String>()
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static Set<String> _split(String cached) => cached
      .split(',')
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toSet();
}
