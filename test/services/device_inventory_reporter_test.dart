import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';
import 'package:appfit_order_agent/services/monitoring/device_inventory_reporter.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

/// Sentry 기기 대장(매장 ↔ 시리얼 ↔ 앱버전) 수집의 전송 규약.
///
/// 정보성 수집이라 **얼마나 안 보내는가**가 핵심이다 — 로그인/영업상태 토글마다
/// 보내면 Sentry 쿼터를 그대로 태운다. 반대로 매장·기기·버전이 바뀐 순간을
/// 놓치면 대장 자체가 틀린다. 그 경계를 고정한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferenceService prefs;
  late SharedPreferences sp;

  const serial = 'H092W24A1G00862';

  PackageInfo pkg(String version, String build) => PackageInfo(
        appName: 'AppFit',
        packageName: 'co.kr.waldlust.order.receive.appfit',
        version: version,
        buildNumber: build,
      );

  /// 전송을 가로채는 리포터. 실제 Sentry 대신 [sent] 에 기록만 한다.
  /// [accepted] false 는 "예외 없이 드롭"(DSN 미주입·큐 포화) 을 흉내낸다.
  ({DeviceInventoryReporter reporter, List<DeviceInventoryRecord> sent})
      buildReporter({
    required DateTime now,
    String version = '2.3.1',
    String build = '195',
    bool accepted = true,
    bool throwOnSend = false,
  }) {
    final sent = <DeviceInventoryRecord>[];
    final reporter = DeviceInventoryReporter(
      prefs,
      DeviceIdentityService(prefs),
      packageInfo: () async => pkg(version, build),
      now: () => now,
      send: (record) async {
        if (throwOnSend) throw StateError('전송 실패');
        sent.add(record);
        return accepted;
      },
    );
    return (reporter: reporter, sent: sent);
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
      PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
      PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
      PreferenceService.KEY_ENVIRONMENT: 'live',
    });
    prefs = PreferenceService();
    await prefs.init();
    sp = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await sp.remove(PreferenceService.KEY_SENTRY_INVENTORY_SIG);
    await sp.remove(PreferenceService.KEY_SENTRY_INVENTORY_AT);
    await sp.remove(PreferenceService.KEY_INSTALL_ID);
    // 시리얼 캐시를 심어 네이티브 조회 경로를 타지 않게 한다(테스트 호스트에는
    // MethodChannel 이 없다). DeviceIdentityService 는 캐시를 먼저 본다.
    await prefs.setCachedDeviceSerial(serial);
  });

  group('전송 판정 (순수 함수)', () {
    final now = DateTime(2026, 9, 4, 10);

    test('전송 이력이 없으면 보낸다', () {
      expect(
        inventoryReportReason(
          signature: 'A|S|1.0.0+1',
          lastSignature: null,
          lastSentAt: null,
          now: now,
        ),
        InventoryReportReason.first,
      );
    });

    test('서명이 같고 주기 이내면 보내지 않는다', () {
      final reason = inventoryReportReason(
        signature: 'A|S|1.0.0+1',
        lastSignature: 'A|S|1.0.0+1',
        lastSentAt: now.subtract(const Duration(days: 6, hours: 23)),
        now: now,
      );
      expect(reason, InventoryReportReason.none);
      expect(reason.shouldReport, isFalse);
    });

    test('서명이 같아도 주기가 지나면 보낸다', () {
      expect(
        inventoryReportReason(
          signature: 'A|S|1.0.0+1',
          lastSignature: 'A|S|1.0.0+1',
          lastSentAt: now.subtract(kDeviceInventoryInterval),
          now: now,
        ),
        InventoryReportReason.intervalElapsed,
      );
    });

    test('서명이 다르면 주기와 무관하게 즉시 보낸다', () {
      for (final changed in [
        'B|S|1.0.0+1', // 매장 전환
        'A|S2|1.0.0+1', // 기기 교체
        'A|S|1.0.1+2', // 앱 업데이트
      ]) {
        expect(
          inventoryReportReason(
            signature: changed,
            lastSignature: 'A|S|1.0.0+1',
            lastSentAt: now,
            now: now,
          ),
          InventoryReportReason.signatureChanged,
          reason: changed,
        );
      }
    });

    test('기기 시계가 뒤로 점프해도 침묵하지 않는다', () {
      // RTC 배터리가 죽은 POS 는 2000년대로 리셋된다. 경과가 음수로 굳으면
      // 그 기기는 대장에서 영구히 사라진다.
      expect(
        inventoryReportReason(
          signature: 'A|S|1.0.0+1',
          lastSignature: 'A|S|1.0.0+1',
          lastSentAt: now,
          now: DateTime(2000, 1, 1),
        ),
        InventoryReportReason.clockRollback,
      );
    });

    test('모든 전송 사유는 로그에 찍을 라벨을 갖는다', () {
      // 로그가 유일한 사후 판정 수단이라 라벨이 비면 판독이 불가능해진다.
      for (final r in InventoryReportReason.values) {
        expect(r.label, isNotEmpty, reason: r.name);
      }
    });
  });

  group('이벤트 태그', () {
    DeviceInventoryRecord record({String? serial, String? installId}) =>
        DeviceInventoryRecord(
          storeId: 'MMTH01050',
          storeName: '동대문구청점',
          serial: serial,
          deviceId: serial ?? 'install-uuid',
          installId: installId,
          idSource: serial == null ? 'installId' : 'serial',
          deviceModel: 'SUNMI T2mini_s',
          deviceManufacturer: 'SUNMI',
          platform: serial == null ? 'windows' : 'android',
          osVersion: '13',
          appVersion: '2.3.1+195',
          signature: 'sig',
        );

    test('조회 대상 값은 contexts 가 아니라 태그로 나간다', () {
      // Sentry 에서 Discover 로 필터·집계 가능한 것은 태그뿐이다.
      final tags = record(serial: serial).toTags();
      expect(tags['report_type'], 'device_inventory');
      expect(tags['id_source'], 'serial');
      expect(tags['os_version'], '13');
      expect(tags['app_version'], '2.3.1+195');
    });

    test('platform 은 Sentry 예약 필드라 device_platform 으로 심는다', () {
      final tags = record(serial: serial).toTags();
      expect(tags.containsKey('platform'), isFalse);
      expect(tags['device_platform'], 'android');
    });

    test('시리얼이 없으면 device_serial 키 자체를 만들지 않는다', () {
      // 빈 값을 심으면 Discover 에서 "시리얼 없음" 과 "미보고" 가 섞인다.
      final identity = _identityOf(serial: null, deviceId: 'install-uuid');
      final tags = deviceScopeTags(identity, installId: 'install-uuid');
      expect(tags.containsKey('device_serial'), isFalse);
      expect(tags['device_id'], 'install-uuid');
    });

    test('install_id 는 시리얼이 있어도 함께 싣는다 (두 행 조인 키)', () {
      // 시리얼 취득 실패 실행과 성공 실행이 대장에 두 행으로 남을 때
      // 이 값만이 같은 물리 기기임을 잇는다.
      final identity = _identityOf(serial: serial, deviceId: serial);
      final tags = deviceScopeTags(identity, installId: 'install-uuid');
      expect(tags['device_serial'], serial);
      expect(tags['install_id'], 'install-uuid');
    });
  });

  group('리포터', () {
    test('첫 로그인에 1건 보내고 서명·시각을 기록한다', () async {
      final now = DateTime(2026, 9, 4, 10);
      final r = buildReporter(now: now);

      await r.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');

      expect(r.sent, hasLength(1));
      final record = r.sent.single;
      expect(record.storeId, 'MMTH01050');
      expect(record.storeName, '동대문구청점');
      expect(record.serial, serial);
      expect(record.appVersion, '2.3.1+195');
      expect(record.signature, 'MMTH01050|$serial|2.3.1+195');

      expect(prefs.getSentryInventorySignature(), record.signature);
      expect(prefs.getSentryInventorySentAt(), now.millisecondsSinceEpoch);
    });

    test('같은 조건으로 다시 호출해도 주기 이내면 보내지 않는다', () async {
      final now = DateTime(2026, 9, 4, 10);
      final first = buildReporter(now: now);
      await first.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');
      expect(first.sent, hasLength(1));

      // 영업상태 토글 등으로 재진입 — 인스턴스가 새로 만들어져도 안 보낸다.
      final again = buildReporter(now: now.add(const Duration(days: 6)));
      await again.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');
      expect(again.sent, isEmpty);
    });

    test('주기가 지나면 같은 조건이라도 다시 보낸다', () async {
      final now = DateTime(2026, 9, 4, 10);
      await buildReporter(now: now)
          .reporter
          .report(storeId: 'MMTH01050', storeName: '동대문구청점');

      final later = now.add(kDeviceInventoryInterval);
      final r = buildReporter(now: later);
      await r.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');

      expect(r.sent, hasLength(1));
      expect(prefs.getSentryInventorySentAt(), later.millisecondsSinceEpoch);
    });

    test('매장이 바뀌면 주기와 무관하게 즉시 보낸다', () async {
      final now = DateTime(2026, 9, 4, 10);
      await buildReporter(now: now)
          .reporter
          .report(storeId: 'MMTH01050', storeName: '동대문구청점');

      final r = buildReporter(now: now.add(const Duration(minutes: 1)));
      await r.reporter.report(storeId: 'MMTH01066', storeName: '약수역점');

      expect(r.sent, hasLength(1));
      expect(r.sent.single.storeId, 'MMTH01066');
    });

    test('7일 내 원래 매장으로 되돌아와도 다시 보낸다', () async {
      // 디듀프 키가 매장 범위였다면 A 의 기록이 아직 유효해 재전송이 막히고,
      // 대장은 이 기기가 아직 B 매장에 있다고 계속 말한다.
      final now = DateTime(2026, 9, 4, 10);
      await buildReporter(now: now)
          .reporter
          .report(storeId: 'MMTH01050', storeName: '동대문구청점');
      await buildReporter(now: now.add(const Duration(minutes: 1)))
          .reporter
          .report(storeId: 'MMTH01066', storeName: '약수역점');

      final back = buildReporter(now: now.add(const Duration(minutes: 2)));
      await back.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');
      expect(back.sent, hasLength(1));
    });

    test('앱 버전이 오르면 즉시 보낸다', () async {
      final now = DateTime(2026, 9, 4, 10);
      await buildReporter(now: now)
          .reporter
          .report(storeId: 'MMTH01050', storeName: '동대문구청점');

      final r = buildReporter(
        now: now.add(const Duration(minutes: 1)),
        version: '2.3.2',
        build: '196',
      );
      await r.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');

      expect(r.sent, hasLength(1));
      expect(r.sent.single.appVersion, '2.3.2+196');
    });

    test('예외 없이 드롭되면(DSN 없음 등) 서명을 기록하지 않는다', () async {
      final now = DateTime(2026, 9, 4, 10);
      final dropped = buildReporter(now: now, accepted: false);
      await dropped.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');

      expect(dropped.sent, hasLength(1)); // 시도는 했다
      expect(prefs.getSentryInventorySignature(), isNull);
      expect(prefs.getSentryInventorySentAt(), isNull);

      final retry = buildReporter(now: now.add(const Duration(minutes: 1)));
      await retry.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');
      expect(retry.sent, hasLength(1));
    });

    test('전송이 예외를 던져도 앱 흐름을 막지 않고 서명도 안 남긴다', () async {
      final now = DateTime(2026, 9, 4, 10);
      final failing = buildReporter(now: now, throwOnSend: true);

      await failing.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');

      expect(prefs.getSentryInventorySignature(), isNull);
      expect(prefs.getSentryInventorySentAt(), isNull);
    });

    test('주기 틱(인자 없는 호출)은 마지막 매장으로 보낸다', () async {
      // 계속 켜둔 기기는 storeProvider 가 값을 내지 않는다 — 7일 규칙이 발동할
      // 유일한 계기가 이 틱이다.
      var clock = DateTime(2026, 9, 4, 10);
      final sent = <DeviceInventoryRecord>[];
      final reporter = DeviceInventoryReporter(
        prefs,
        DeviceIdentityService(prefs),
        packageInfo: () async => pkg('2.3.1', '195'),
        now: () => clock,
        send: (record) async {
          sent.add(record);
          return true;
        },
      );

      await reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');
      expect(sent, hasLength(1));

      // 주기 이내의 틱은 조용하다.
      clock = clock.add(const Duration(hours: 6));
      await reporter.report();
      expect(sent, hasLength(1));

      clock = clock.add(kDeviceInventoryInterval);
      await reporter.report();
      expect(sent, hasLength(2));
      expect(sent.last.storeId, 'MMTH01050');
      expect(sent.last.storeName, '동대문구청점');
    });

    test('동시 호출은 1건만 보낸다', () async {
      final now = DateTime(2026, 9, 4, 10);
      final r = buildReporter(now: now);

      await Future.wait([
        r.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점'),
        r.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점'),
      ]);

      expect(r.sent, hasLength(1));
    });

    test('매장이 확정되기 전에는 아무것도 보내지 않는다', () async {
      final r = buildReporter(now: DateTime(2026, 9, 4, 10));
      await r.reporter.report();
      expect(r.sent, isEmpty);
      expect(prefs.getSentryInventorySignature(), isNull);
    });

    test('시리얼이 없는 기기(Windows)는 설치 UUID 로 대장에 남는다', () async {
      await sp.remove(PreferenceService.KEY_DEVICE_SERIAL);
      final installId = await prefs.getOrCreateInstallId();

      final r = buildReporter(now: DateTime(2026, 9, 4, 10));
      await r.reporter.report(storeId: 'MMTH01050', storeName: '동대문구청점');

      final record = r.sent.single;
      expect(record.serial, isNull);
      expect(record.deviceId, installId);
      expect(record.installId, installId);
      expect(record.idSource, 'installId');
      // 시리얼 자리가 비면 서명은 설치 UUID 로 대체된다.
      expect(record.signature, contains(installId));
    });
  });
}

DeviceIdentity _identityOf({String? serial, required String deviceId}) =>
    DeviceIdentity(
      projectName: null,
      shopName: null,
      shopCode: null,
      deviceModel: 'SUNMI T2mini_s',
      serial: serial,
      deviceId: deviceId,
      idSource: serial == null ? 'installId' : 'serial',
      deviceManufacturer: 'SUNMI',
      platform: serial == null ? 'windows' : 'android',
      osVersion: '13',
    );
