import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 빠른 메뉴 지정 저장/복원. docs/TESTING.md 의 PreferenceService seam 규약 사용.
///
/// 이 파일이 존재하는 이유: 최초 구현이 매장 ID 를 `getStoreId()`
/// (`KOKONUT_STORE_ID`) 에서 읽었는데 **그 키를 쓰는 코드가 어디에도 없어**
/// 항상 null 이었다. 그 결과 저장이 조용히 스킵되고 화면에는 아무 표시도 남지
/// 않았다. 매장 ID 출처가 다시 어긋나면 여기서 잡힌다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
      PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
      PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
      PreferenceService.KEY_ENVIRONMENT: 'live',
    });
    await PreferenceService().init();
  });

  group('빠른 메뉴 지정 저장', () {
    test('로그인 매장(getId)이 있으면 저장·복원된다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');

      final ok = await prefs.setFastMenuIds({'AME', 'internal-AME'});

      expect(ok, isTrue, reason: '매장 ID 가 있으면 저장에 성공해야 한다');
      expect(prefs.getFastMenuIds(), {'AME', 'internal-AME'});
    });

    test('매장 ID 가 없으면 false 를 돌려준다 (조용히 성공한 척하지 않는다)', () async {
      final prefs = PreferenceService();
      // saveId 미호출 = 로그인 전 상태.
      expect(await prefs.setFastMenuIds({'AME'}), isFalse);
      expect(prefs.getFastMenuIds(), isEmpty);
    });

    test('매장이 다르면 서로의 지정을 보지 않는다', () async {
      final prefs = PreferenceService();

      await prefs.saveId('TPCP001');
      await prefs.setFastMenuIds({'AME'});

      await prefs.saveId('MHST007');
      expect(prefs.getFastMenuIds(), isEmpty,
          reason: '매장 전환 시 이전 매장 상품 ID 가 새 매장에 잘못 매칭되면 안 된다');

      await prefs.setFastMenuIds({'LATTE'});
      expect(prefs.getFastMenuIds(), {'LATTE'});

      // 원래 매장으로 돌아오면 그 매장 지정이 그대로 남아 있어야 한다.
      await prefs.saveId('TPCP001');
      expect(prefs.getFastMenuIds(), {'AME'});
    });

    test('매장 ID 대소문자가 섞여도 같은 키를 본다', () async {
      // saveId/getId 가 대문자로 정규화하므로 키도 안정적이어야 한다.
      final prefs = PreferenceService();
      await prefs.saveId('tpcp001');
      await prefs.setFastMenuIds({'AME'});

      await prefs.saveId('TPCP001');
      expect(prefs.getFastMenuIds(), {'AME'});
    });

    test('빈 집합 저장은 지정 해제로 동작한다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');
      await prefs.setFastMenuIds({'AME'});

      expect(await prefs.setFastMenuIds(<String>{}), isTrue);
      expect(prefs.getFastMenuIds(), isEmpty);
    });
  });

  group('빠른 메뉴 모드/표시 기본값', () {
    test('기본은 전부 꺼짐 — 켜기 전까지 종전 동작', () {
      final prefs = PreferenceService();
      expect(prefs.getFastMenuMode(), 0);
      expect(prefs.getFastMenuMarker(), isFalse);
      expect(prefs.getFastMenuIds(), isEmpty);
    });

    test('모드/표시는 매장과 무관하게 기기 단위로 저장된다', () async {
      final prefs = PreferenceService();
      await prefs.setFastMenuMode(2);
      await prefs.setFastMenuMarker(true);

      expect(prefs.getFastMenuMode(), 2);
      expect(prefs.getFastMenuMarker(), isTrue);
    });
  });
}
