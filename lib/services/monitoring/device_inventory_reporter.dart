import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 기기 대장 이벤트를 다시 보내는 주기. 서명이 그대로여도 이 간격이 지나면
/// 한 번 더 보내 "지금도 살아 있는 기기" 를 구분한다.
const Duration kDeviceInventoryInterval = Duration(days: 7);

/// 대장 이벤트 식별 태그 값. Slack 알림 규칙의 제외 필터가 이 값을 본다
/// (`sentry_alerts/routes.json` 의 `exclude_tags`). 양쪽을 함께 바꿔야 한다.
const String kDeviceInventoryReportType = 'device_inventory';

/// 대장 이벤트를 한 이슈로 묶는 fingerprint. 매장마다 새 이슈가 생기면 이슈
/// 목록이 수백 건으로 오염된다 — 조회는 이슈가 아니라 Discover 태그 집계로 한다.
const List<String> kDeviceInventoryFingerprint = ['device-inventory'];

/// Sentry 이슈 제목이 되는 고정 메시지. 매장명 등 변동값을 넣으면 제목이
/// 첫 이벤트의 매장으로 굳어버리므로 넣지 않는다(변동값은 태그로).
/// `[info]` 접두사는 이 이슈가 장애가 아님을 제목만으로 읽히게 한다.
const String kDeviceInventoryMessage = '[info][inventory] 기기 대장 보고';

/// Sentry 로 보낼 기기 대장 1건.
///
/// **조회 대상 값은 전부 태그다** — Sentry 에서 Discover 로 필터·집계할 수 있는
/// 것은 태그뿐이고 `contexts` 는 이벤트 상세에서 눈으로만 보인다. 대장은 기계가
/// 집계하는 용도라 [toTags] 가 정본이고, [toExtras] 는 사람이 읽는 사본이다.
class DeviceInventoryRecord {
  final String storeId;
  final String storeName;

  /// 하드웨어 시리얼. **Windows 는 항상 null** (설치 UUID 만 있다).
  final String? serial;
  final String deviceId;

  /// 설치 UUID. 시리얼 유무와 무관하게 싣는다 — 시리얼 취득에 실패했던 실행과
  /// 성공한 실행이 대장에 두 행으로 남을 때 이 값이 유일한 조인 키다.
  final String? installId;
  final String idSource;
  final String deviceModel;
  final String deviceManufacturer;
  final String platform;
  final String osVersion;

  /// `x.y.z+n` 형식.
  final String appVersion;

  /// 디듀프 판정용 서명. `매장ID|시리얼(없으면 deviceId)|앱버전`.
  final String signature;

  const DeviceInventoryRecord({
    required this.storeId,
    required this.storeName,
    required this.serial,
    required this.deviceId,
    required this.installId,
    required this.idSource,
    required this.deviceModel,
    required this.deviceManufacturer,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.signature,
  });

  /// 이벤트 전용 태그. 기기 식별 태그(`device_serial`/`device_id`/`device_model`/
  /// `install_id`)와 매장 태그(`store_id`/`store_name`)는 scope 에 이미 있어
  /// 이벤트가 그대로 물려받으므로 여기서 다시 심지 않는다.
  ///
  /// ⚠️ `platform` 은 Sentry **예약 필드**(이벤트 속성)라 같은 이름의 커스텀
  /// 태그를 만들면 검색에서 예약 값에 가려진다 — `device_platform` 으로 쓴다.
  Map<String, String> toTags() => {
        'report_type': kDeviceInventoryReportType,
        'id_source': idSource,
        'device_platform': platform,
        'os_version': osVersion,
        'app_version': appVersion,
      };

  /// 사람이 이벤트를 열어 읽는 사본. 조회에는 쓰이지 않는다.
  Map<String, dynamic> toExtras() => {
        'store_id': storeId,
        'store_name': storeName,
        'device_serial': serial ?? '-',
        'device_id': deviceId,
        'install_id': installId ?? '-',
        'id_source': idSource,
        'device_model': deviceModel,
        'manufacturer': deviceManufacturer,
        'device_platform': platform,
        'os_version': osVersion,
        'app_version': appVersion,
      };
}

/// 모든 이벤트에 따라붙을 기기 식별 태그.
///
/// 시리얼이 없는 기기(Windows)는 `device_serial` 키 **자체를 만들지 않는다** —
/// 빈 값이나 `-` 를 심으면 Discover 집계에서 "시리얼 없음" 과 "미보고" 가 섞인다.
/// 조회는 `!has:device_serial` 로 한다.
Map<String, String> deviceScopeTags(
  DeviceIdentity identity, {
  String? installId,
}) {
  final serial = identity.serial;
  return {
    if (serial != null && serial.isNotEmpty) 'device_serial': serial,
    'device_id': identity.deviceId,
    'device_model': identity.deviceModel,
    if (installId != null && installId.isNotEmpty) 'install_id': installId,
  };
}

/// 대장 전송 사유. 로그에 그대로 찍혀 "왜 보냈나 / 왜 안 보냈나" 를 사후에
/// 판정하게 한다 — 대장은 7일에 1건이라 조용한 게 정상이고, 사유가 없으면
/// "스킵" 과 "호출 자체가 안 됨" 이 구분되지 않는다.
enum InventoryReportReason {
  first('첫 보고'),
  signatureChanged('서명 변경'),
  intervalElapsed('주기 경과'),
  clockRollback('시계 되돌림'),
  none('스킵');

  const InventoryReportReason(this.label);

  final String label;

  bool get shouldReport => this != InventoryReportReason.none;
}

/// 대장 판정: 서명이 바뀌었거나 마지막 전송 후 [kDeviceInventoryInterval] 이
/// 지났으면 보낸다. 전송 이력이 없으면 무조건 보낸다.
///
/// 시각·저장소·Sentry 를 모두 배제한 순수 함수라 단위 테스트로 고정한다.
InventoryReportReason inventoryReportReason({
  required String signature,
  required String? lastSignature,
  required DateTime? lastSentAt,
  required DateTime now,
}) {
  if (lastSignature == null || lastSentAt == null) {
    return InventoryReportReason.first;
  }
  if (lastSignature != signature) return InventoryReportReason.signatureChanged;
  final elapsed = now.difference(lastSentAt);
  // 기기 시계가 뒤로 점프하면(RTC 배터리가 죽은 POS 는 2000년대로 리셋된다)
  // 경과가 음수로 굳어 그 기기가 대장에서 영구히 사라진다. 되돌림도 전송 사유다.
  if (elapsed.isNegative) return InventoryReportReason.clockRollback;
  if (elapsed >= kDeviceInventoryInterval) {
    return InventoryReportReason.intervalElapsed;
  }
  return InventoryReportReason.none;
}

/// 기본 전송 경로 — Sentry 정보 이벤트 1건. 실제로 큐에 실렸으면 true.
///
/// `captureMessage` 는 **실패해도 예외를 던지지 않고** `SentryId.empty()` 를
/// 반환한다(DSN 미주입 빌드, SDK 태스크큐 포화, beforeSend 드롭). 빈 ID 를
/// 성공으로 적으면 그 기기는 다음 주기까지 대장에서 사라지므로 구분해야 한다.
/// 오프라인은 여기 해당하지 않는다 — 디스크 캐시 후 재전송되며 정상 ID 를 준다.
Future<bool> sendInventoryToSentry(DeviceInventoryRecord record) async {
  final id = await Sentry.captureMessage(
    kDeviceInventoryMessage,
    level: SentryLevel.info,
    withScope: (scope) {
      record.toTags().forEach(scope.setTag);
      scope.setContexts('device_inventory', record.toExtras());
      scope.fingerprint = kDeviceInventoryFingerprint;
    },
  );
  return id != const SentryId.empty();
}

/// 매장 ↔ 기기 시리얼 ↔ 앱버전 대장을 Sentry 로 수집한다.
///
/// 두 가지를 한다:
/// 1. **scope 태그**([deviceScopeTags]) — 이후 모든 이벤트에 따라붙어 오류가
///    어느 기기에서 났는지 특정할 수 있게 한다.
/// 2. **정보 이벤트 1건** — 오류가 한 번도 안 나는 기기도 대장에 남게 한다.
///    서명 변경 또는 7일 경과일 때만 보낸다(쿼터 보호).
///
/// 경고·차단은 하지 않는다. 순수 정보성 수집이다.
class DeviceInventoryReporter {
  final PreferenceService _prefs;
  final DeviceIdentityService _identity;
  final Future<PackageInfo> Function() _packageInfo;
  final Future<bool> Function(DeviceInventoryRecord record) _send;
  final DateTime Function() _now;

  DeviceInventoryReporter(
    this._prefs,
    this._identity, {
    Future<PackageInfo> Function()? packageInfo,
    Future<bool> Function(DeviceInventoryRecord record)? send,
    DateTime Function()? now,
  })  : _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _send = send ?? sendInventoryToSentry,
        _now = now ?? DateTime.now;

  /// scope 태그는 앱 실행당 1회면 충분하다(Sentry scope 는 계속 유지된다).
  bool _scopeApplied = false;

  /// 호출부(monitoringSyncProvider)가 매장 상태 변경마다 재진입하므로 겹침 차단.
  bool _inFlight = false;

  /// 주기 틱(인자 없는 호출)이 쓸 마지막 매장. 매장은 서버 응답(storeProvider)이
  /// 정본이다 — `DeviceIdentity.shopName/shopCode` 를 대신 쓰면 안 된다. 그 값은
  /// 첫 `resolve()` 에서 굳고 `invalidate()` 는 Windows 화이트리스트 매장에서만
  /// 호출돼(fleet_provider), Android 는 매장 전환 후에도 옛 매장이 남는다.
  /// `KEY_STORE_NAME` 도 앱 어디서도 쓰지 않아 항상 비어 있다.
  String? _lastStoreId;
  String _lastStoreName = '';

  /// 매장 정보가 확정된 뒤, 그리고 주기 틱마다 호출한다. 인자를 생략하면 마지막
  /// 매장을 쓴다(주기 틱 경로). 실패해도 앱 흐름에 영향을 주지 않는다.
  Future<void> report({String? storeId, String? storeName}) async {
    if (storeId != null && storeId.isNotEmpty) {
      _lastStoreId = storeId;
      _lastStoreName = storeName ?? '';
    }
    final activeStoreId = _lastStoreId;
    // 매장이 확정되기 전(로그인 전·로그아웃 후)에는 대장이 의미가 없다.
    if (activeStoreId == null || activeStoreId.isEmpty) {
      logger.i('[INVENTORY] 스킵 — 매장 미확정');
      return;
    }

    if (_inFlight) {
      logger.i('[INVENTORY] 스킵 — 직전 보고 진행 중');
      return;
    }
    _inFlight = true;
    try {
      final identity = await _identity.resolve();
      final installId = _prefs.getInstallIdOrNull();
      _applyScopeTags(identity, installId);

      final pkg = await _packageInfo();
      final appVersion = '${pkg.version}+${pkg.buildNumber}';
      // 서명에 매장명은 넣지 않는다 — 매장 리네임은 7일 주기 때 반영되면 충분하고,
      // 서버 표기 흔들림으로 재전송이 터지는 편이 손해다.
      final signature =
          '$activeStoreId|${identity.serial ?? identity.deviceId}|$appVersion';

      final lastAtMs = _prefs.getSentryInventorySentAt();
      final lastSentAt = lastAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAtMs);
      final now = _now();
      final reason = inventoryReportReason(
        signature: signature,
        lastSignature: _prefs.getSentryInventorySignature(),
        lastSentAt: lastSentAt,
        now: now,
      );
      if (!reason.shouldReport) {
        // shouldReport 가 false 인 유일한 경우가 `none` 이고, 그건 이력이 둘 다
        // 있을 때만 나온다(없으면 `first`). 그래도 ?. 로 받아 판정 규칙이
        // 바뀌어도 로그 한 줄 때문에 크래시하지 않게 한다.
        final due = lastSentAt?.add(kDeviceInventoryInterval);
        logger.i('[INVENTORY] 스킵 — 서명 동일, 다음 보고 예정 '
            '${due?.toIso8601String() ?? "-"} ($signature)');
        return;
      }
      logger.i('[INVENTORY] 보고 시도 — ${reason.label} · $signature '
          '(serial=${identity.serial ?? "-"}, source=${identity.idSource})');

      final sent = await _send(DeviceInventoryRecord(
        storeId: activeStoreId,
        storeName: _lastStoreName,
        serial: identity.serial,
        deviceId: identity.deviceId,
        installId: installId,
        idSource: identity.idSource,
        deviceModel: identity.deviceModel,
        deviceManufacturer: identity.deviceManufacturer,
        platform: identity.platform,
        osVersion: identity.osVersion,
        appVersion: appVersion,
        signature: signature,
      ));

      // 실제로 전송된 뒤에만 기록한다 — 드롭을 성공으로 적으면 그 기기는
      // 다음 주기까지 대장에서 사라진다.
      if (!sent) {
        // Sentry 가 이벤트를 받지 않았다(쿼터 소진 429·DSN 미주입·큐 포화).
        // 다음 트리거에서 다시 시도한다.
        logger.w('[INVENTORY] 전송 드롭 — Sentry 미수용 · $signature');
        return;
      }
      await _prefs.setSentryInventorySent(signature, now);
      logger.i('[INVENTORY] 전송 완료 — $signature');
    } catch (e, s) {
      logger.w('[INVENTORY] 전송 실패', error: e, stackTrace: s);
    } finally {
      _inFlight = false;
    }
  }

  void _applyScopeTags(DeviceIdentity identity, String? installId) {
    if (_scopeApplied) return;
    Sentry.configureScope((scope) {
      deviceScopeTags(identity, installId: installId).forEach(scope.setTag);
    });
    // 예외가 나면 다음 호출에서 다시 시도할 수 있도록 성공 후에 잠근다.
    _scopeApplied = true;
  }
}
