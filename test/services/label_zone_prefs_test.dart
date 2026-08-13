import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 라벨 구역(제조 구역별 프린터 분담) 설정 저장/복원.
/// docs/TESTING.md 의 PreferenceService seam 규약 사용.
///
/// 빠른 메뉴와 같은 매장별 키 방식이라 같은 함정을 공유한다 — 매장 ID 를
/// `getStoreId()`(쓰는 코드가 없어 항상 null)에서 읽으면 저장이 조용히 스킵된다.
/// 여기서 잡는다. ([fast_menu_prefs_test.dart] 참조)
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

  group('기본값 — 켜기 전까지 종전 동작', () {
    test('배정도 담당도 비어 있다 (= 전량 primary + 전량 출력)', () {
      final prefs = PreferenceService();
      expect(prefs.getLabelTargetAssignment(), isEmpty);
      expect(prefs.getLabelLocalTargets(), isEmpty);
    });
  });

  group('카테고리→구역 배정 저장', () {
    test('로그인 매장(getId)이 있으면 저장·복원된다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');

      final ok = await prefs.setLabelTargetAssignment({'TKP1006': 'zone2'});

      expect(ok, isTrue);
      expect(prefs.getLabelTargetAssignment(), {'TKP1006': 'zone2'});
    });

    test('매장 ID 가 없으면 false — 조용히 성공한 척하지 않는다', () async {
      final prefs = PreferenceService();
      expect(
          await prefs.setLabelTargetAssignment({'TKP1006': 'zone2'}), isFalse);
      expect(prefs.getLabelTargetAssignment(), isEmpty);
    });

    test('매장이 다르면 서로의 배정을 보지 않는다', () async {
      final prefs = PreferenceService();

      await prefs.saveId('TPCP001');
      await prefs.setLabelTargetAssignment({'TKP1006': 'zone2'});

      await prefs.saveId('MHST007');
      expect(prefs.getLabelTargetAssignment(), isEmpty,
          reason: '카테고리 코드는 매장마다 뜻이 달라 이월되면 안 된다');

      await prefs.saveId('TPCP001');
      expect(prefs.getLabelTargetAssignment(), {'TKP1006': 'zone2'});
    });

    test('빈 값 항목은 저장 시 걸러진다 (미매핑=primary 와 뜻이 겹치지 않게)', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');

      await prefs.setLabelTargetAssignment({
        'TKP1006': 'zone2',
        'TKP9999': '', // 빈 타깃
        '': 'zone3', // 빈 카테고리
      });

      expect(prefs.getLabelTargetAssignment(), {'TKP1006': 'zone2'});
    });

    test('빈 맵 저장은 배정 해제로 동작한다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');
      await prefs.setLabelTargetAssignment({'TKP1006': 'zone2'});

      expect(await prefs.setLabelTargetAssignment({}), isTrue);
      expect(prefs.getLabelTargetAssignment(), isEmpty);
    });
  });

  group('이 단말이 담당하는 구역 저장', () {
    test('저장·복원된다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');

      expect(await prefs.setLabelLocalTargets({'zone2'}), isTrue);
      expect(prefs.getLabelLocalTargets(), {'zone2'});
    });

    test('빈 집합 저장은 "전부 담당" 으로 되돌린다 — 라벨 소실 0 이 기본', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');
      await prefs.setLabelLocalTargets({'zone2'});

      expect(await prefs.setLabelLocalTargets(<String>{}), isTrue);
      expect(prefs.getLabelLocalTargets(), isEmpty);
    });

    test('매장 ID 대소문자가 섞여도 같은 키를 본다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('tpcp001');
      await prefs.setLabelLocalTargets({'zone3'});

      await prefs.saveId('TPCP001');
      expect(prefs.getLabelLocalTargets(), {'zone3'});
    });

    test('배정과 담당은 서로 독립적으로 저장된다', () async {
      final prefs = PreferenceService();
      await prefs.saveId('TPCP001');

      await prefs.setLabelTargetAssignment({'TKP1006': 'zone2'});
      await prefs.setLabelLocalTargets({'zone2'});

      expect(prefs.getLabelTargetAssignment(), {'TKP1006': 'zone2'});
      expect(prefs.getLabelLocalTargets(), {'zone2'});

      // 담당만 지워도 배정(매장 정책)은 남아야 한다.
      await prefs.setLabelLocalTargets(<String>{});
      expect(prefs.getLabelTargetAssignment(), {'TKP1006': 'zone2'});
    });
  });
}
