import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

/// 라벨 출력 카테고리/서브정보 설정의 저장 규약.
///
/// 값이 매장별 POS 코드라 **매장 범위 키**로 저장한다. 기기 전역으로 두면 다른
/// 매장으로 로그인했을 때 이전 매장의 코드가 그대로 적용돼 엉뚱한 상품이 걸러진다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences sp;
  late PreferenceService prefs;

  setUpAll(() async {
    // PreferenceService 는 factory 싱글톤 → 실제 init() 으로 우회.
    // 마이그레이션/프린터·업데이트 기본값/환경 복원 분기는 마커 키로 스킵.
    SharedPreferences.setMockInitialValues(<String, Object>{
      V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
      PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
      PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
      PreferenceService.KEY_ENVIRONMENT: 'live',
    });
    prefs = PreferenceService();
    await prefs.init();
    // init() 이 이미 getInstance() 를 호출했으므로 같은 인스턴스가 돌아온다.
    // PreferenceService 는 캐싱 없이 라이브로 읽으므로 키를 직접 지울 수 있다.
    sp = await SharedPreferences.getInstance();
  });

  setUp(() async {
    // 매장 흔적을 모두 지워 "매장 미확정" 상태에서 시작한다.
    await prefs.clearSessionStoreId();
    await sp.remove(PreferenceService.KEY_MID);
    for (final storeId in ['STOREA', 'STOREB', 'STOREC']) {
      await sp.remove(
          '${PreferenceService.KEY_LABEL_CATEGORY_FILTER_ON_PREFIX}$storeId');
      await sp.remove(
          '${PreferenceService.KEY_LABEL_CATEGORY_KEYS_PREFIX}$storeId');
      await sp.remove(
          '${PreferenceService.KEY_LABEL_SUBINFO_GROUPS_PREFIX}$storeId');
    }
  });

  group('매장 범위 저장', () {
    test('매장이 확정되지 않으면 저장하지 않고 false 를 반환한다', () async {
      expect(await prefs.setLabelCategoryFilterOn(true), isFalse);
      expect(await prefs.setLabelCategoryKeys({'c:A'}), isFalse);
      expect(await prefs.setLabelSubInfoGroups(['G1']), isFalse);

      // 조회는 기본값으로 수렴 — 켜진 것처럼 보이면 안 된다.
      expect(prefs.getLabelCategoryFilterOn(), isFalse);
      expect(prefs.getLabelCategoryKeys(), isEmpty);
      expect(prefs.getLabelSubInfoGroups(), isEmpty);
    });

    test('저장한 매장에서만 읽힌다 (매장 전환 시 격리)', () async {
      await prefs.setSessionStoreId('STOREA');

      expect(await prefs.setLabelCategoryFilterOn(true), isTrue);
      expect(await prefs.setLabelCategoryKeys({'c:A', 'c:B'}), isTrue);
      expect(await prefs.setLabelSubInfoGroups(['G2', 'G1']), isTrue);

      // 다른 매장으로 전환하면 아무것도 안 보인다.
      await prefs.setSessionStoreId('STOREB');
      expect(prefs.getLabelCategoryFilterOn(), isFalse);
      expect(prefs.getLabelCategoryKeys(), isEmpty);
      expect(prefs.getLabelSubInfoGroups(), isEmpty);

      // 돌아오면 그대로 남아 있다.
      await prefs.setSessionStoreId('STOREA');
      expect(prefs.getLabelCategoryFilterOn(), isTrue);
      expect(prefs.getLabelCategoryKeys(), {'c:A', 'c:B'});
      expect(prefs.getLabelSubInfoGroups(), ['G2', 'G1']);
    });

    test('세션 매장이 없으면 로그인 ID 로 폴백한다 (getActiveStoreId 규약)', () async {
      await prefs.saveId('storec');

      expect(await prefs.setLabelSubInfoGroups(['G1']), isTrue);
      expect(prefs.getLabelSubInfoGroups(), ['G1']);
    });
  });

  group('직렬화', () {
    setUp(() async => prefs.setSessionStoreId('STOREA'));

    test('서브정보는 선택 순서를 보존한다 (순서 = 인쇄 순서)', () async {
      await prefs.setLabelSubInfoGroups(['G_TEMP', 'G_SIZE', 'G_BEAN']);
      expect(prefs.getLabelSubInfoGroups(), ['G_TEMP', 'G_SIZE', 'G_BEAN']);

      await prefs.setLabelSubInfoGroups(['G_BEAN', 'G_TEMP']);
      expect(prefs.getLabelSubInfoGroups(), ['G_BEAN', 'G_TEMP']);
    });

    test('빈 항목은 저장 시 걸러진다', () async {
      await prefs.setLabelSubInfoGroups(['G1', '', '  ', 'G2']);
      expect(prefs.getLabelSubInfoGroups(), ['G1', 'G2']);
    });

    test('빈 집합 저장은 해제와 같다', () async {
      await prefs.setLabelCategoryKeys({'c:A'});
      await prefs.setLabelCategoryKeys({});
      expect(prefs.getLabelCategoryKeys(), isEmpty);
    });

    test('JSON 이 손상돼도 빈 값으로 흡수한다 (라벨 소실 0)', () async {
      await sp.setString(
        '${PreferenceService.KEY_LABEL_CATEGORY_KEYS_PREFIX}STOREA',
        '{not json',
      );
      expect(prefs.getLabelCategoryKeys(), isEmpty);
    });
  });
}
