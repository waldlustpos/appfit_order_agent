import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/sales_off_provider.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기기 전원종료·앱 종료 시 매장을 CLOSED 로 내리는 경로의 가드를 고정한다.
///
/// 여기서 지키는 불변식은 셋이다.
/// 1. KDS 보조단말(자동접수 OFF)은 **절대** 보내지 않는다 — storeId 를 메인단말과
///    공유하므로, 보내면 영업 중인 메인단말의 상태를 덮어쓴다.
/// 2. 미로그인 기기는 보내지 않는다.
/// 3. 전원종료 경로와 detached 경로가 겹쳐도 PUT 은 한 번뿐이다.
class _FakeApiService implements ApiService {
  final List<({String storeId, bool isOn})> statusCalls = [];

  /// true 면 updateShopOperatingStatus 가 실패(false)를 반환한다.
  bool shouldFail = false;

  @override
  Future<bool> updateShopOperatingStatus(String storeId, bool isOn) async {
    statusCalls.add((storeId: storeId, isOn: isOn));
    return !shouldFail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({ProviderContainer container, _FakeApiService api})> _build() async {
  final api = _FakeApiService();
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
  ]);
  addTearDown(container.dispose);
  return (container: container, api: api);
}

/// PreferenceService 는 factory 싱글톤이라 테스트마다 mock 값을 새로 심고
/// init() 으로 다시 읽힌다. 마이그레이션/기본값 재조정 분기는 마커로 건너뛴다.
Future<void> _prefs({
  String? storeId,
  bool kdsMode = false,
  bool kdsAcceptOrders = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
    PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
    PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
    PreferenceService.KEY_ENVIRONMENT: 'live',
    if (storeId != null) PreferenceService.KEY_SESSION_STORE_ID: storeId,
    PreferenceService.KEY_IS_KDS_MODE: kdsMode,
    PreferenceService.KEY_KDS_ACCEPT_ORDERS: kdsAcceptOrders,
  });
  await PreferenceService().init();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KDS 가드 — 종료 버튼(home_screen._exitApp) 과 같은 규칙', () {
    test('메인모드면 보낸다', () async {
      await _prefs(storeId: 'MMTH00101');
      final b = await _build();
      final sender = b.container.read(shutdownSalesOffSenderProvider);

      expect(await sender.sendSalesOff(reason: 'shutdown'), isTrue);
      expect(b.api.statusCalls, [(storeId: 'MMTH00101', isOn: false)]);
    });

    test('KDS + 자동접수 OFF 는 보내지 않는다 (메인단말 상태 보호)', () async {
      await _prefs(storeId: 'MMTH00101', kdsMode: true);
      final b = await _build();
      final sender = b.container.read(shutdownSalesOffSenderProvider);

      // 보낼 일이 없는 것도 "할 일을 마친" 것이므로 true — 네이티브가 실패로
      // 오해해 post-mortem 진단을 돌리면 안 된다.
      expect(await sender.sendSalesOff(reason: 'shutdown'), isTrue);
      expect(b.api.statusCalls, isEmpty);
    });

    test('KDS + 자동접수 ON 은 단독 운영이므로 보낸다', () async {
      await _prefs(
          storeId: 'MMTH00101', kdsMode: true, kdsAcceptOrders: true);
      final b = await _build();
      final sender = b.container.read(shutdownSalesOffSenderProvider);

      expect(await sender.sendSalesOff(reason: 'shutdown'), isTrue);
      expect(b.api.statusCalls, [(storeId: 'MMTH00101', isOn: false)]);
    });

    test('메인모드 + 자동접수 ON 도 보낸다', () async {
      await _prefs(storeId: 'MMTH00101', kdsAcceptOrders: true);
      final b = await _build();
      final sender = b.container.read(shutdownSalesOffSenderProvider);

      expect(await sender.sendSalesOff(reason: 'shutdown'), isTrue);
      expect(b.api.statusCalls, [(storeId: 'MMTH00101', isOn: false)]);
    });
  });

  test('매장 ID 가 없으면(미로그인) 보내지 않는다', () async {
    await _prefs();
    final b = await _build();
    final sender = b.container.read(shutdownSalesOffSenderProvider);

    expect(await sender.sendSalesOff(reason: 'shutdown'), isTrue);
    expect(b.api.statusCalls, isEmpty);
  });

  test('성공 후 두 번째 호출(detached)은 중복 전송하지 않는다', () async {
    await _prefs(storeId: 'MMTH00101');
    final b = await _build();
    final sender = b.container.read(shutdownSalesOffSenderProvider);

    expect(await sender.sendSalesOff(reason: 'shutdown'), isTrue);
    expect(await sender.sendSalesOff(reason: 'detached'), isTrue);
    expect(b.api.statusCalls, hasLength(1));
  });

  test('실패했으면 남은 경로가 다시 시도할 수 있다', () async {
    await _prefs(storeId: 'MMTH00101');
    final b = await _build();
    final sender = b.container.read(shutdownSalesOffSenderProvider);

    b.api.shouldFail = true;
    expect(await sender.sendSalesOff(reason: 'shutdown'), isFalse);

    b.api.shouldFail = false;
    expect(await sender.sendSalesOff(reason: 'detached'), isTrue);
    expect(b.api.statusCalls, hasLength(2));
  });
}
