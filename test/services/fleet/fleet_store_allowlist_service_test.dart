import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:appfit_order_agent/services/fleet/fleet_store_allowlist_service.dart';
import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

/// 관제 대상 매장 화이트리스트 판정.
///
/// 여기서 고정하는 핵심 계약은 **조회 실패가 관제를 끄지 않는다**는 것이다.
/// 매장 인터넷이 잠깐 끊겼다고 파일럿 기기가 대시보드에서 사라지면, 정작 관제가
/// 필요한 상황에서 관제가 없어진다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences sp;

  setUpAll(() async {
    // PreferenceService 는 factory 싱글톤 → 실제 init() 으로 우회.
    // 마이그레이션/프린터·업데이트 기본값/환경 복원 분기는 마커 키로 스킵.
    SharedPreferences.setMockInitialValues(<String, Object>{
      V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
      PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
      PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
      PreferenceService.KEY_ENVIRONMENT: 'live',
    });
    await PreferenceService().init();
    // init() 이 이미 getInstance() 를 호출했으므로 같은 인스턴스가 돌아온다.
    // PreferenceService 는 캐싱 없이 라이브로 읽으므로 여기서 키를 직접
    // 지우면 "아직 한 번도 못 받아봄" 상태를 만들 수 있다.
    sp = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await sp.remove(PreferenceService.KEY_FLEET_STORE_ALLOWLIST);
  });

  FleetStoreAllowlistService serviceWith(Future<Object?> Function() fetcher) =>
      FleetStoreAllowlistService(PreferenceService(), fetcher: fetcher);

  FleetStoreAllowlistService serviceReturning(Object? data) =>
      serviceWith(() async => data);

  group('목록 파싱', () {
    test('표준 형식 — stores 배열의 매장만 대상', () async {
      final service = serviceReturning(<String, Object?>{
        'version': 1,
        'stores': <String>['MHST00001', 'TPCP00002'],
      });

      expect(await service.refresh(), isTrue);
      expect(service.isTargeted('MHST00001'), isTrue);
      expect(service.isTargeted('TPCP00002'), isTrue);
      expect(service.isTargeted('PAIK00002'), isFalse);
      expect(service.cachedCount, 2);
    });

    test('대소문자·공백은 정규화해서 비교한다', () async {
      final service = serviceReturning(<String, Object?>{
        'stores': <String>[' mhst00001 '],
      });

      expect(await service.refresh(), isTrue);
      expect(service.isTargeted('MHST00001'), isTrue);
      expect(service.isTargeted('mhst00001'), isTrue);
      expect(service.isTargeted('  MHST00001  '), isTrue);
    });

    test('최상위가 배열인 형태도 허용한다', () async {
      final service = serviceReturning(<String>['MHST00001']);

      expect(await service.refresh(), isTrue);
      expect(service.isTargeted('MHST00001'), isTrue);
    });

    test('stores 누락은 오류가 아니라 "대상 없음"', () async {
      final service = serviceReturning(<String, Object?>{'version': 1});

      expect(await service.refresh(), isTrue);
      expect(service.isTargeted('MHST00001'), isFalse);
      expect(service.cachedCount, 0);
    });

    test('빈 배열은 전부 OFF — 서버가 파일럿을 되돌린 상태', () async {
      final service = serviceReturning(<String, Object?>{
        'stores': <String>[],
      });

      expect(await service.refresh(), isTrue);
      expect(service.isTargeted('MHST00001'), isFalse);
      expect(service.cachedCount, 0);
    });

    test('문자열이 아닌 항목은 조용히 버린다', () async {
      final service = serviceReturning(<String, Object?>{
        'stores': <Object?>['MHST00001', 42, null, ''],
      });

      expect(await service.refresh(), isTrue);
      expect(service.cachedCount, 1);
      expect(service.isTargeted('MHST00001'), isTrue);
    });
  });

  group('조회 실패 — 캐시 폴백', () {
    test('네트워크 실패는 캐시를 덮지 않고 이전 판정을 유지한다', () async {
      final ok = serviceReturning(<String, Object?>{
        'stores': <String>['MHST00001'],
      });
      expect(await ok.refresh(), isTrue);

      final failing = serviceWith(() async => throw Exception('offline'));
      expect(await failing.refresh(), isFalse);

      // 캐시가 살아 있으므로 파일럿 기기는 계속 대상이다.
      expect(failing.isTargeted('MHST00001'), isTrue);
      expect(failing.cachedCount, 1);
    });

    test('형식 불일치 응답도 캐시를 덮지 않는다', () async {
      final ok = serviceReturning(<String, Object?>{
        'stores': <String>['MHST00001'],
      });
      expect(await ok.refresh(), isTrue);

      // 404 HTML 페이지가 문자열로 들어오는 경우 등.
      final malformed = serviceReturning('<html>Not Found</html>');
      expect(await malformed.refresh(), isFalse);
      expect(malformed.isTargeted('MHST00001'), isTrue);
    });

    test('stores 가 배열이 아니면 캐시를 덮지 않는다', () async {
      final ok = serviceReturning(<String, Object?>{
        'stores': <String>['MHST00001'],
      });
      expect(await ok.refresh(), isTrue);

      final malformed = serviceReturning(<String, Object?>{'stores': 'MHST*'});
      expect(await malformed.refresh(), isFalse);
      expect(malformed.isTargeted('MHST00001'), isTrue);
    });

    test('캐시가 없는 채로 실패하면 OFF — 최초 설치 기기의 기본값', () async {
      final service = serviceWith(() async => throw Exception('offline'));

      expect(await service.refresh(), isFalse);
      expect(service.isTargeted('MHST00001'), isFalse);
      expect(service.cachedCount, isNull);
    });
  });

  group('매장 코드 입력', () {
    test('null·빈 문자열은 대상이 아니다 (로그인 전 상태)', () async {
      final service = serviceReturning(<String, Object?>{
        'stores': <String>['MHST00001'],
      });
      expect(await service.refresh(), isTrue);

      expect(service.isTargeted(null), isFalse);
      expect(service.isTargeted(''), isFalse);
      expect(service.isTargeted('   '), isFalse);
    });

    test('부분 일치는 대상이 아니다 (완전일치만)', () async {
      final service = serviceReturning(<String, Object?>{
        'stores': <String>['MHST00001'],
      });
      expect(await service.refresh(), isTrue);

      expect(service.isTargeted('MHST'), isFalse);
      expect(service.isTargeted('MHST000010'), isFalse);
      expect(service.isTargeted('MHST0000'), isFalse);
    });
  });
}
