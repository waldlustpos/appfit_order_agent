// fake_async 는 flutter_test 의 전이 의존성(pubspec.lock 에 이미 고정)이며,
// 새 직접 의존성 추가 없이 타이머 검증에 사용한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:appfit_order_agent/constants/order_constants.dart';
import 'package:appfit_order_agent/core/orders/alert_manager.dart';
import 'package:appfit_order_agent/core/orders/sound_service.dart';
import 'package:appfit_order_agent/models/force_bulk_done_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/providers/misc_providers.dart';
import 'package:appfit_order_agent/providers/order/order_provider.dart';
import 'package:appfit_order_agent/providers/order/order_timer_manager.dart';
import 'package:appfit_order_agent/providers/store_provider.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/output_queue_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/services/soundgraph_hook.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OrderProvider 3-way 주문 유입 characterization 테스트.
///
/// 실제 OrderProvider(Order notifier)를 ProviderContainer + overrides 로
/// 통째로 인스턴스화하여, 다음 "현재 동작"을 고정한다:
/// - (a) queueOrderExternal 의 (orderId, status) 단위 중복 enqueue 차단 (ProcessedOrderCache)
/// - (b) refreshOrders 의 부활 차단 (RecentRemovals + isActiveOrderStatus 사전 필터)
/// - (c) refreshOrders 의 상태 다운그레이드 차단 (resolveMergedStatus 연동)
/// - (d) 소켓 유입(append, 미정렬) vs refreshOrders(orderedAt 오름차순 전체 재정렬)
///
/// 우회한 외부 의존:
/// - audioplayers: OrderProvider 필드 이니셜라이저가 AudioPlayer() 를 즉시 생성하므로
///   메서드 채널 4종('xyz.luan/audioplayers*')을 mock handler 로 무력화.
/// - PreferenceService: preferenceServiceProvider 로 주입되며 getter 가
///   SharedPreferences 를 라이브로 읽는다(캐싱 없음). 대부분의 테스트는
///   KEY_AUTO_RECEIPT=false 로 자동접수 PUT 체인을 차단하고 유입 경로만 관찰하며,
///   그룹 (e) 는 setAutoReceipt(true) 로 토글해 자동접수 ON 분기를 검증한다.
/// - ApiService/AlertManager/OutputQueueService/PrintService/SoundService 는
///   수동 fake (noSuchMethod fallback — 예기치 않은 호출은 즉시 표면화).
///
/// 시간 의존(버퍼 1s / 배치 200ms / 소켓체크 500ms)은 OrderProvider.build 가
/// 플랫폼 채널 mock 응답·비동기 API 와 얽혀 있어 fakeAsync zone 으로 감싸지 않고
/// 실시간 대기로 제어한다 (개별 매니저의 fakeAsync 검증은 order_queue_manager_test 참고).
/// 폴링 타이머 wiring 은 OrderTimerManager 를 직접 fakeAsync 로 고정한다.

// ---------------------------------------------------------------------------
// 수동 fakes
// ---------------------------------------------------------------------------

/// 유입 경로가 사용하는 메서드만 구현한 fake. 나머지는 noSuchMethod (호출 시 throw).
class _FakeApiService implements ApiService {
  /// getOrders(refreshOrders/초기 로드)가 돌려줄 서버 응답.
  List<OrderModel> ordersResponse = const <OrderModel>[];
  int getOrdersCallCount = 0;

  /// updateOrderStatus 스크립트 결과 및 호출 기록.
  bool updateOrderStatusResult = true;
  final List<(String orderId, OrderStatus status)> statusUpdates = [];

  /// updateOrderStatus 로 넘어온 readyTime(준비시간, 분). 자동접수는 선택 UI 가
  /// 없어 고정 기본값을 넘기므로 그 값이 실제로 실려 나가는지 확인하는 용도.
  final List<String?> readyTimes = [];

  /// 응답을 붙잡아 두는 게이트. null 이면 즉시 반환(기존 동작 그대로).
  /// 느린 네트워크의 in-flight 구간을 재현할 때만 주입한다.
  Completer<bool>? updateGate;

  @override
  Future<List<OrderModel>> getOrders(
    String storeId, {
    String? startDate,
    String? endDate,
    OrderStatus? orderStatus,
  }) async {
    getOrdersCallCount++;
    return List<OrderModel>.of(ordersResponse);
  }

  @override
  Future<List<OrderModel>> getNewOrders(
    String storeId, {
    String? startDate,
    String? endDate,
  }) async =>
      const <OrderModel>[];

  @override
  Future<bool> updateOrderStatus(
    String storeId,
    OrderStatus status,
    String orderId, {
    String? readyTime,
  }) async {
    statusUpdates.add((orderId, status));
    readyTimes.add(readyTime);
    final gate = updateGate;
    if (gate != null) return gate.future;
    return updateOrderStatusResult;
  }

  /// forceCompleteOrders 호출 기록 (요청마다 orderNos 사본 1건).
  final List<List<String>> forceCalls = [];

  /// 서버 응답 스크립트. null 이면 요청한 주문 전부 성공으로 응답한다.
  ForceBulkDoneResponse? forceResponse;

  /// 응답을 붙잡아 두는 게이트 (in-flight 구간 재현용).
  Completer<ForceBulkDoneResponse>? forceGate;

  /// 던질 예외. ApiService 는 실패 시 ApiException 을 던지므로 그 계약을 재현한다.
  Object? forceThrows;

  @override
  Future<ForceBulkDoneResponse> forceCompleteOrders(
    String storeId,
    List<String> orderNos,
  ) async {
    forceCalls.add(List<String>.of(orderNos));
    final gate = forceGate;
    if (gate != null) return gate.future;
    final err = forceThrows;
    if (err != null) throw err;
    return forceResponse ?? _forceAllSuccess(orderNos);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 요청한 주문이 전부 성공한 응답.
ForceBulkDoneResponse _forceAllSuccess(List<String> orderNos) =>
    ForceBulkDoneResponse(
      targetOrderCount: orderNos.length,
      updateSuccessCount: orderNos.length,
      updateFailCount: 0,
      results: [
        for (final no in orderNos)
          ForceBulkDoneResult(orderNo: no, success: true),
      ],
    );

/// storeProvider 오버라이드용 fake notifier. build 만 대체한다.
class _FakeStore extends Store {
  _FakeStore(this._model);

  final StoreModel? _model;

  @override
  Future<StoreModel?> build() async => _model;
}

/// 알림(소리/오버레이/앱바) 트리거를 기록하는 fake.
/// 세 신호가 서로 다른 축(소리=주문서·알림소리 설정, 오버레이·앱바=노출 설정)을
/// 따르므로 횟수뿐 아니라 플래그 조합까지 남긴다.
class _FakeAlertManager implements AlertManager {
  int triggerCount = 0;
  final List<({bool sound, bool overlay, bool appBar})> calls = [];

  @override
  void triggerNewOrderAlert({
    bool playSound = true,
    bool triggerOverlay = true,
    bool triggerAppBar = true,
  }) {
    triggerCount++;
    calls.add((
      sound: playSound,
      overlay: triggerOverlay,
      appBar: triggerAppBar,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 출력 큐 투입 기록만 남기는 fake (실제 프린터/직렬화 없음).
class _FakeOutputQueueService implements OutputQueueService {
  final List<String> addedOrderIds = [];
  final List<String> labelOnlyOrderIds = [];

  @override
  void add(
    OrderModel order, {
    bool playSound = true,
    bool printLabel = true,
    bool forceOrderReceipt = false,
  }) {
    addedOrderIds.add(order.orderId);
  }

  @override
  void addLabelOnly(OrderModel order) {
    labelOnlyOrderIds.add(order.orderId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 사운드그래프 전송 발화를 기록하는 fake hook.
/// 실제 전송(외부 HTTP)은 하지 않고 호출된 orderId 만 순서대로 남긴다.
class _RecordingSoundGraphHook extends SoundGraphHook {
  final List<String> acceptedOrderIds = [];

  @override
  void onAccepted(OrderModel order) => acceptedOrderIds.add(order.orderId);
}

/// build() 의 조기 초기화(ref.read)만 통과시키는 빈 fake.
class _FakePrintService implements PrintService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// stopBlinking() 경유 stop() 호출만 무력화하는 fake.
class _FakeSoundService implements SoundService {
  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// 헬퍼
// ---------------------------------------------------------------------------

/// 오늘 hour:minute 고정 시각. belongsToToday(orderedAt 날짜 비교) 통과용.
DateTime _todayAt(int hour, [int minute = 0]) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

OrderModel _order({
  required String orderNo,
  String shopOrderNo = '0001',
  OrderStatus status = OrderStatus.NEW,
  DateTime? orderedAt,
  DateTime? updateTime,
  String source = '',
}) {
  final at = orderedAt ?? _todayAt(12);
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: shopOrderNo,
    orderStatus: status.name,
    orderedAt: at,
    totalAmount: 9000,
    status: status,
    storeId: 'STORE-1',
    userId: 'user-1',
    ordererName: '홍길동',
    orderCount: '1',
    paymentAmount: 9000,
    discountAmount: 0,
    paymentType: 'CARD',
    paymentCode: 'CARD',
    menus: const <OrderMenuModel>[],
    orderType: 'T',
    kdsOrderType: 1,
    kioskId: 'kiosk-1',
    source: source,
    updateTime: updateTime ?? at,
  );
}

typedef _Harness = ({
  ProviderContainer container,
  Order notifier,
  _FakeApiService api,
  _FakeOutputQueueService output,
  _FakeAlertManager alerts,
  _RecordingSoundGraphHook soundGraph,
});

/// OrderProvider 전체를 인스턴스화하고 초기화 비동기 체인이 끝날 때까지 대기.
///
/// 700ms 대기 이유: build() 가 microtask 로 초기 refreshOrders 를 수행하고,
/// 500ms 후 Future.delayed 로 소켓 상태 점검(checkAndFixSocketConnection)을
/// 실행한다. 컨테이너 dispose 후 해당 콜백이 ref 를 만지면 StateError 가 나므로
/// 테스트 본문 진입 전에 소화시킨다.
Future<_Harness> _buildProvider({
  List<OrderModel> initialServerOrders = const <OrderModel>[],
  bool withStore = true,
}) async {
  final api = _FakeApiService()..ordersResponse = initialServerOrders;
  final output = _FakeOutputQueueService();
  final alerts = _FakeAlertManager();
  final soundGraph = _RecordingSoundGraphHook();
  final store = withStore
      ? StoreModel(storeId: 'STORE-1', name: '테스트매장', isOpen: true)
      : null;

  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    storeProvider.overrideWith(() => _FakeStore(store)),
    alertManagerProvider.overrideWithValue(alerts),
    outputQueueServiceProvider.overrideWithValue(output),
    printServiceProvider.overrideWithValue(_FakePrintService()),
    soundAppServiceProvider.overrideWithValue(_FakeSoundService()),
    soundGraphHookProvider.overrideWithValue(soundGraph),
  ]);
  addTearDown(container.dispose);

  // storeProvider 를 먼저 resolve — 실서비스에서는 로그인 흐름이 store 를 선해석한
  // 뒤 OrderProvider 가 빌드된다. 미해석 상태로 빌드하면 _orderDataInitialize 의
  // microtask 가 storeId='' 를 보고 초기 로드를 스킵한다 (현재 동작).
  await container.read(storeProvider.future);
  final notifier = container.read(orderProvider.notifier);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  return (
    container: container,
    notifier: notifier,
    api: api,
    output: output,
    alerts: alerts,
    soundGraph: soundGraph,
  );
}

/// 실시간 대기 단축 헬퍼.
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// audioplayers 메서드/이벤트 채널 mock.
///
/// 현재는 soundAppServiceProvider 가 fake 로 대체돼 있고 OrderProvider 도
/// AudioPlayer 를 들고 있지 않아(유령 플레이어 제거) 실제 플레이어가 생성되지
/// 않는다. 다만 재생 경로가 다시 실물 AudioPlayer 를 잡게 되면 create →
/// 이벤트 채널 listen 까지 성공해야 setVolume/setAudioContext 의 비동기
/// 오류(unhandled)가 테스트를 죽이지 않으므로 안전망으로 남겨 둔다. 이벤트
/// 채널 이름에 uuid playerId 가 포함되므로 create 호출 시점에 동적으로 등록한다.
void _mockAudioPlayersChannels(TestDefaultBinaryMessenger messenger) {
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        final playerId = args['playerId']! as String;
        messenger.setMockMethodCallHandler(
          MethodChannel('xyz.luan/audioplayers/events/$playerId'),
          (MethodCall _) async => null,
        );
      }
      return null;
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (MethodCall _) async => null,
  );
  // EventChannel 의 listen/cancel 도 같은 이름의 MethodChannel mock 으로 응답.
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global/events'),
    (MethodCall _) async => null,
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _mockAudioPlayersChannels(binding.defaultBinaryMessenger);

    // PreferenceService 는 factory 싱글톤 → 실제 init() 으로 우회.
    // 마이그레이션/프린터·업데이트 기본값/환경 복원 분기는 마커 키로 스킵.
    SharedPreferences.setMockInitialValues(<String, Object>{
      V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
      PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
      PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
      PreferenceService.KEY_ENVIRONMENT: 'live',
      // 자동접수 OFF — 유입 경로 자체만 관찰 (PUT 체인/출력 사이드이펙트 차단).
      // 주의: getAutoReceipt() 의 기본값은 true (현재 동작).
      PreferenceService.KEY_AUTO_RECEIPT: false,
      // 키오스크 주문 노출 ON 고정 — 이 파일의 관심사는 유입/자동접수 체인이지
      // 노출 필터가 아니다. 기본값은 OFF 이고 init() 이 한 번 더 강제로 OFF 로
      // 덮어쓰므로(마커), 마커를 미리 세워 그 재조정을 건너뛰고 노출을 켜 둔다.
      // (노출 OFF 상태의 동작은 아래 (h) 그룹이 따로 검증한다)
      PreferenceService.KEY_KIOSK_SETTINGS_RECONCILED: true,
      PreferenceService.KEY_SHOW_KIOSK_ORDER: true,
    });
    await PreferenceService().init();
  });

  group('(a) 소켓 유입 dedup — queueOrderExternal + ProcessedOrderCache', () {
    test('동일 (orderId, status) 재유입은 큐 진입 자체가 차단됨', () async {
      final h = await _buildProvider();
      final a = _order(orderNo: 'A');

      h.notifier.queueOrderExternal(a);
      expect(h.notifier.hasPendingExternal, isTrue);

      await _wait(1400); // 버퍼(1s) flush + 첫 emit
      var state = h.container.read(orderProvider);
      expect(state.orders.map((o) => o.orderId), ['A']);
      expect(state.orders.single.status, OrderStatus.NEW);
      expect(h.alerts.triggerCount, 1); // NEW 알림 1회

      // 같은 (A, NEW) 재유입 — 캐시 hit 으로 enqueue 자체가 스킵된다.
      h.notifier.queueOrderExternal(a);
      expect(h.notifier.hasPendingExternal, isFalse);

      await _wait(1400);
      state = h.container.read(orderProvider);
      expect(state.orders.length, 1);
      expect(h.alerts.triggerCount, 1); // 추가 알림 없음
    });

    test('같은 주문이라도 status 전이(NEW→PREPARING)는 dedup 을 통과', () async {
      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1400);

      h.notifier.queueOrderExternal(_order(
        orderNo: 'A',
        status: OrderStatus.PREPARING,
        updateTime: _todayAt(12, 5),
      ));
      expect(h.notifier.hasPendingExternal, isTrue);

      await _wait(450); // 상태 업데이트 배치 윈도우(200ms)
      final state = h.container.read(orderProvider);
      expect(state.orders.single.status, OrderStatus.PREPARING);
      expect(state.activeOrderCount, 1); // PREPARING 은 활성 카운트 포함
    });
  });

  group('(b) refreshOrders 부활 차단 — RecentRemovals × active 상태', () {
    test('종결(DONE) 직후 서버 stale 응답이 NEW 로 돌아와도 부활하지 않음', () async {
      final a = _order(orderNo: 'A');
      final h = await _buildProvider(initialServerOrders: [a]);

      // 초기 로드로 A(NEW) 가 state 에 존재.
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.NEW,
      );

      // 수동 완료 처리 → RecentRemovals 마킹 + 즉시 UI 반영.
      final ok = await h.notifier.updateOrderStatus(a, OrderStatus.DONE);
      expect(ok, isTrue);
      expect(h.api.statusUpdates, [('A', OrderStatus.DONE)]);
      await _wait(450); // 종결 배치(queueOrderExternal 경유) 소화
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.DONE,
      );

      // 서버 replication lag: 같은 주문이 active(NEW) 로 되돌아오는 응답.
      h.api.ordersResponse = [a];
      await h.notifier.refreshOrders();

      // 현재 동작 고정: 부활이 차단되고, 직전 DONE 항목도 서버 목록 대체로
      // 함께 사라진다 (서버가 종결 상태로 응답할 때까지 일시 비표시).
      expect(h.container.read(orderProvider).orders, isEmpty);
    });

    test('서버가 종결(DONE) 상태로 정상 응답하면 통과되어 목록 유지', () async {
      final a = _order(orderNo: 'A');
      final h = await _buildProvider(initialServerOrders: [a]);

      await h.notifier.updateOrderStatus(a, OrderStatus.DONE);
      await _wait(450);

      h.api.ordersResponse = [
        a.copyWith(status: OrderStatus.DONE, orderStatus: '2020'),
      ];
      await h.notifier.refreshOrders();

      final state = h.container.read(orderProvider);
      expect(state.orders.map((o) => o.orderId), ['A']);
      expect(state.orders.single.status, OrderStatus.DONE);
    });
  });

  group('(c) refreshOrders 상태 다운그레이드 차단 — resolveMergedStatus 연동', () {
    test('로컬 PREPARING 인데 서버가 구버전 NEW 를 돌려주면 로컬 상태 유지', () async {
      final h = await _buildProvider();
      h.notifier.queueOrderExternal(
        _order(orderNo: 'A', status: OrderStatus.PREPARING),
      );
      await _wait(450);
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.PREPARING,
      );

      h.api.ordersResponse = [_order(orderNo: 'A', status: OrderStatus.NEW)];
      await h.notifier.refreshOrders();

      final state = h.container.read(orderProvider);
      expect(state.orders.single.status, OrderStatus.PREPARING);
      // 다운그레이드 차단 시 orderStatus 코드도 로컬 값을 유지한다.
      expect(state.orders.single.orderStatus, OrderStatus.PREPARING.name);
    });

    test('서버가 더 진행된 상태(READY)면 서버 상태로 갱신(업그레이드 통과)', () async {
      final h = await _buildProvider();
      h.notifier.queueOrderExternal(
        _order(orderNo: 'A', status: OrderStatus.PREPARING),
      );
      await _wait(450);

      h.api.ordersResponse = [_order(orderNo: 'A', status: OrderStatus.READY)];
      await h.notifier.refreshOrders();

      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.READY,
      );
    });

    test('CANCELLED 는 터미널 — 로컬 PREPARING 이어도 서버 CANCELLED 우선', () async {
      final h = await _buildProvider();
      h.notifier.queueOrderExternal(
        _order(orderNo: 'A', status: OrderStatus.PREPARING),
      );
      await _wait(450);

      h.api.ordersResponse = [
        _order(orderNo: 'A', status: OrderStatus.CANCELLED),
      ];
      await h.notifier.refreshOrders();

      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.CANCELLED,
      );
    });
  });

  group('(d) 유입 후 state.orders 정렬 — 현재 동작 고정', () {
    test(
        '현재 동작 고정(버그 의심): 소켓 유입은 emit 순서(shopOrderNo 오름차순)로 append 만 — '
        'orderedAt 재정렬 없음', () async {
      final h = await _buildProvider();
      // B 가 더 이른 주문시간(12:30)이지만 shopOrderNo 가 큼.
      final b = _order(
          orderNo: 'B', shopOrderNo: '0002', orderedAt: _todayAt(12, 30));
      final a =
          _order(orderNo: 'A', shopOrderNo: '0001', orderedAt: _todayAt(13));

      h.notifier.queueOrderExternal(b);
      h.notifier.queueOrderExternal(a);
      await _wait(2100); // flush(1s) + 2번째 emit(0.5s)

      final state = h.container.read(orderProvider);
      // emit 은 shopOrderNo 오름차순(A→B), state 는 append 순서 그대로.
      expect(state.orders.map((o) => o.orderId).toList(), ['A', 'B']);
      // 주문시간 기준으로는 역순 — refreshOrders 전까지 orderedAt 정렬이 보장되지 않는다.
      expect(
        state.orders[0].orderedAt.isAfter(state.orders[1].orderedAt),
        isTrue,
      );
    });

    test('refreshOrders 는 orderedAt 오름차순으로 전체 재정렬', () async {
      // 서버 응답 순서가 [13:00, 12:30] 이어도 정렬되어 [12:30, 13:00].
      final h = await _buildProvider(initialServerOrders: [
        _order(orderNo: 'A', shopOrderNo: '0001', orderedAt: _todayAt(13)),
        _order(orderNo: 'B', shopOrderNo: '0002', orderedAt: _todayAt(12, 30)),
      ]);

      final state = h.container.read(orderProvider);
      expect(state.orders.map((o) => o.orderId).toList(), ['B', 'A']);
    });
  });

  group('(e) 자동접수 ON 체인 — PreferenceService seam', () {
    // PreferenceService 는 preferenceServiceProvider 로 주입되고 getter 가
    // SharedPreferences 를 라이브로 읽으므로(캐싱 없음), setAutoReceipt 로
    // 값을 토글한 뒤 build 하면 자동접수 ON 분기를 그대로 탈 수 있다.
    // (Phase 1 에서 '싱글톤이라 per-test 제어 불가' 로 미커버였던 경로)
    test('자동접수 ON + 비-KDS 면 신규 NEW 주문을 PREPARING 으로 PUT (updateOrderStatus 호출)',
        () async {
      await PreferenceService().setAutoReceipt(true);
      addTearDown(() => PreferenceService().setAutoReceipt(false));

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1600); // 버퍼(1s) flush + emit + 자동접수 microtask + PUT

      // 자동접수 → updateOrderStatus(A, PREPARING) 가 ApiService 로 호출됨.
      expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
      // 준비시간은 선택 UI 가 없으므로 고정 기본값(분)이 실려 나간다.
      expect(h.api.readyTimes, contains('$kAutoAcceptReadyTimeMinutes'));
      // 로컬 상태도 PREPARING 으로 전이.
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.PREPARING,
      );
    });

    test('자동접수 OFF 면 신규 NEW 주문에 updateOrderStatus 를 호출하지 않음', () async {
      // setUpAll 기본값(false) — 명시적으로 대비군 고정.
      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1600);

      expect(h.api.statusUpdates, isEmpty);
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.NEW,
      );
    });

    test('자동접수 OFF 여도 키오스크 주문 + KioskAlwaysAutoAccept ON 이면 PREPARING 으로 PUT',
        () async {
      // 자동접수(픽업)는 OFF(setUpAll 기본값)지만 키오스크 전용 설정은 ON.
      await PreferenceService().setKioskAlwaysAutoAccept(true);
      addTearDown(() => PreferenceService().setKioskAlwaysAutoAccept(true));

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A', source: 'WALD_KIOSK'));
      await _wait(1600);

      // 키오스크 오버라이드로 자동접수 → updateOrderStatus(A, PREPARING).
      expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.PREPARING,
      );
    });

    test('자동접수 OFF + 키오스크 주문 + KioskAlwaysAutoAccept OFF 면 PUT 하지 않음',
        () async {
      await PreferenceService().setKioskAlwaysAutoAccept(false);
      addTearDown(() => PreferenceService().setKioskAlwaysAutoAccept(true));

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A', source: 'WALD_KIOSK'));
      await _wait(1600);

      expect(h.api.statusUpdates, isEmpty);
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.NEW,
      );
    });

    test('KioskAlwaysAutoAccept ON 이라도 비키오스크 주문은 자동접수 OFF 를 따름(오버라이드 스코프 검증)',
        () async {
      await PreferenceService().setKioskAlwaysAutoAccept(true);
      addTearDown(() => PreferenceService().setKioskAlwaysAutoAccept(true));

      final h = await _buildProvider();
      // source 미지정 = 비키오스크. 키오스크 오버라이드가 걸리면 안 됨.
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1600);

      expect(h.api.statusUpdates, isEmpty);
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.NEW,
      );
    });
  });

  group('(f) updateShouldNotify — 무변경 폴링 통지 차단 (딥 비교)', () {
    test('내용이 동일한 refreshOrders 재실행은 watcher 에 통지되지 않음', () async {
      // PREPARING 사용: NEW 는 알림/blink 부수 경로가 얽혀 관찰이 흐려진다.
      final h = await _buildProvider(
        initialServerOrders: [
          _order(orderNo: 'A', status: OrderStatus.PREPARING)
        ],
      );

      var notifications = 0;
      h.container.listen(orderProvider, (prev, next) => notifications++);

      // 폴링 재현: 서버가 동일 내용을 새 인스턴스/새 리스트로 응답.
      h.api.ordersResponse = [
        _order(orderNo: 'A', status: OrderStatus.PREPARING),
      ];
      await h.notifier.refreshOrders();
      await _wait(50);

      expect(notifications, 0, reason: '내용 동일(OrderState == 딥 비교) → 통지 원천 차단');
      // state 자체는 조용히 최신 인스턴스로 교체되어 있어야 한다.
      expect(h.container.read(orderProvider).orders.single.status,
          OrderStatus.PREPARING);
    });

    test('주문 내용이 실제로 바뀌면(PREPARING→READY) 정상 통지된다', () async {
      final h = await _buildProvider(
        initialServerOrders: [
          _order(orderNo: 'A', status: OrderStatus.PREPARING)
        ],
      );

      var notifications = 0;
      h.container.listen(orderProvider, (prev, next) => notifications++);

      h.api.ordersResponse = [_order(orderNo: 'A', status: OrderStatus.READY)];
      await h.notifier.refreshOrders();
      await _wait(50);

      expect(notifications, greaterThan(0),
          reason: '상태 업그레이드는 딥 비교에서도 차이 → 통지 유지');
      expect(h.container.read(orderProvider).orders.single.status,
          OrderStatus.READY);
    });
  });

  group('refreshOrders 가드 — 매장 ID 부재', () {
    test('storeId 가 없으면 에러만 설정하고 종료 (주문 목록 비움 유지)', () async {
      final h = await _buildProvider(withStore: false);
      expect(h.api.getOrdersCallCount, 0); // 초기 로드도 스킵됨

      await h.notifier.refreshOrders();

      final state = h.container.read(orderProvider);
      expect(state.error, '매장 ID를 찾을 수 없습니다.');
      expect(state.isLoading, isFalse);
      expect(state.orders, isEmpty);
      expect(h.api.getOrdersCallCount, 0);
    });
  });

  group('폴링 타이머 wiring — OrderTimerManager', () {
    // 폴링은 설계상 refreshOrders 로 단일화되어 있다. 과거 폴링 전용 경로
    // (_pollNewOrders → _processPollingNewOrders → _mergeOrdersIntoUnfilteredList)는
    // dead wiring 으로 확인되어 삭제됨 (docs/REFACTORING.md Phase 2-1).
    OrderTimerManager buildManager({
      required void Function() onRefresh,
    }) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = Provider<OrderTimerManager>(
        (ref) => OrderTimerManager(
          ref,
          onRefreshOrders: onRefresh,
        ),
      );
      return container.read(provider);
    }

    test('restartPolling 주기 타이머는 onRefreshOrders 를 지정 간격으로 호출', () {
      fakeAsync((async) {
        var refreshes = 0;
        final m = buildManager(
          onRefresh: () => refreshes++,
        );

        m.restartPolling(5);
        async.elapse(const Duration(seconds: 16));

        expect(refreshes, 3); // 5s 주기 3회
        m.dispose();
      });
    });

    test('setupPollingTimer 는 30s 스타트업 후 주기적으로 onRefreshOrders 호출', () {
      fakeAsync((async) {
        var refreshes = 0;
        final m = buildManager(
          onRefresh: () => refreshes++,
        );

        // 테스트 환경의 AppFitConfig 는 기본 live 환경 → baseUrl 비어있지 않음.
        m.setupPollingTimer(false);
        async.elapse(const Duration(seconds: 29));
        expect(refreshes, 0); // 스타트업 딜레이(30s) 이전엔 미발화

        // 30s 후 connected 간격(60s) 주기 시작.
        async.elapse(const Duration(seconds: 1 + 60));
        expect(refreshes, 1);
        m.dispose();
      });
    });
  });

  // -------------------------------------------------------------------------
  // (f) 상태변경 in-flight 락
  //
  // "이미 그 상태면 조기 return" 가드는 첫 요청이 **성공해서 state 가 갱신된
  // 뒤에만** 작동한다. 응답이 20초 넘게 걸리는 저품질 네트워크에서는 그 구간이
  // 통째로 무방비여서, 반응 없는 버튼을 연타하면 같은 주문에 PUT 이 N번 나갔다.
  // (2026-08-07 매장 장애)
  // -------------------------------------------------------------------------
  group('(f) updateOrderStatus in-flight 락', () {
    test('응답 대기 중 같은 주문을 다시 요청하면 API 는 한 번만 나간다', () async {
      final h = await _buildProvider();
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      final gate = Completer<bool>();
      h.api.updateGate = gate;

      final first = h.notifier.updateOrderStatus(a, OrderStatus.READY);
      await _wait(20); // 첫 호출이 API await 지점에 도달하도록

      final second = await h.notifier.updateOrderStatus(a, OrderStatus.READY);

      expect(second, isFalse,
          reason: 'in-flight 거절은 반드시 false — true 면 호출부가 "성공" 로그를 남겨 '
              '장애 분석에서 진짜 성공과 구분되지 않는다');
      expect(h.api.statusUpdates.length, 1);

      gate.complete(true);
      expect(await first, isTrue);
    });

    test('서로 다른 주문은 서로를 막지 않는다', () async {
      final h = await _buildProvider();
      final gate = Completer<bool>();
      h.api.updateGate = gate;

      final a = h.notifier.updateOrderStatus(
          _order(orderNo: 'A', status: OrderStatus.PREPARING),
          OrderStatus.READY);
      await _wait(20);
      final b = h.notifier.updateOrderStatus(
          _order(orderNo: 'B', status: OrderStatus.PREPARING),
          OrderStatus.READY);
      await _wait(20);

      expect(h.api.statusUpdates.length, 2);

      gate.complete(true);
      await Future.wait([a, b]);
    });

    test('실패로 끝나도 락이 풀려 다시 시도할 수 있다', () async {
      final h = await _buildProvider();
      final a = _order(orderNo: 'C', status: OrderStatus.PREPARING);
      h.api.updateOrderStatusResult = false;

      expect(await h.notifier.updateOrderStatus(a, OrderStatus.READY), isFalse);
      expect(await h.notifier.updateOrderStatus(a, OrderStatus.READY), isFalse);

      // 연타 차단이 아니라 "순차 재시도" 는 통과해야 한다 — 실패 후 운영자가
      // 다시 누르는 것은 정당한 요청이다.
      expect(h.api.statusUpdates.length, 2);
    });
  });

  group('(g) forceCompleteOrder — 접수 단계에서 바로 완료', () {
    test('PREPARING 주문이 DONE 이 되고, 단건 orderNos 로 요청한다', () async {
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      final h = await _buildProvider(initialServerOrders: [a]);

      expect(await h.notifier.forceCompleteOrder(a), isTrue);

      // 일괄 API 지만 단건으로만 쏜다 — 여기가 무너지면 매장 전체가 완료된다.
      expect(h.api.forceCalls, [
        ['A']
      ]);
      // 단계별 PUT 은 타지 않는다(픽업 요청을 건너뛰는 것이 이 경로의 존재 이유).
      expect(h.api.statusUpdates, isEmpty);

      await _wait(450); // 종결 배치(queueOrderExternal 경유) 소화
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.DONE,
      );
    });

    test('완료 후 서버 stale 응답이 PREPARING 으로 돌아와도 부활하지 않음', () async {
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      final h = await _buildProvider(initialServerOrders: [a]);

      await h.notifier.forceCompleteOrder(a);
      await _wait(450);

      // 강제 완료도 RecentRemovals 마킹을 거쳐야 한다. 이걸 빠뜨리면 폴링
      // replication lag 이 완료한 주문을 되살린다 (단계별 PUT 과 동일 계약).
      h.api.ordersResponse = [a];
      await h.notifier.refreshOrders();

      expect(h.container.read(orderProvider).orders, isEmpty);
    });

    test('results 가 success:false 면 상태를 바꾸지 않는다 (200 이어도 실패)', () async {
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      final h = await _buildProvider(initialServerOrders: [a]);

      // 부분 실패해도 HTTP 200 이다. 카운터가 아니라 건별 결과로 판정해야 한다.
      h.api.forceResponse = const ForceBulkDoneResponse(
        targetOrderCount: 1,
        updateSuccessCount: 0,
        updateFailCount: 1,
        results: [
          ForceBulkDoneResult(
            orderNo: 'A',
            success: false,
            errorCode: 'INVALID_ORDER_STATUS',
            message: '처리할 수 없는 주문 상태입니다.',
          ),
        ],
      );

      expect(await h.notifier.forceCompleteOrder(a), isFalse);
      await _wait(450);
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.PREPARING,
      );
    });

    test('요청한 주문이 results 에 아예 없으면 실패로 본다', () async {
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      final h = await _buildProvider(initialServerOrders: [a]);

      // 대상에서 빠져 결과가 없는 응답. updateSuccessCount 만 보면 "1건 성공"
      // 으로 오독하기 쉬운 모양이라 일부러 카운터를 성공으로 채워 둔다.
      h.api.forceResponse = const ForceBulkDoneResponse(
        targetOrderCount: 1,
        updateSuccessCount: 1,
        updateFailCount: 0,
        results: [ForceBulkDoneResult(orderNo: 'OTHER', success: true)],
      );

      expect(await h.notifier.forceCompleteOrder(a), isFalse);
      await _wait(450);
      expect(
        h.container.read(orderProvider).orders.single.status,
        OrderStatus.PREPARING,
      );
    });

    test('이미 DONE 인 주문은 요청을 아낀다', () async {
      final a = _order(orderNo: 'A', status: OrderStatus.DONE);
      final h = await _buildProvider(initialServerOrders: [a]);

      expect(await h.notifier.forceCompleteOrder(a), isTrue);
      expect(h.api.forceCalls, isEmpty);
    });

    test('응답 대기 중 같은 주문을 다시 요청하면 API 는 한 번만 나간다', () async {
      final h = await _buildProvider();
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      final gate = Completer<ForceBulkDoneResponse>();
      h.api.forceGate = gate;

      final first = h.notifier.forceCompleteOrder(a);
      await _wait(20); // 첫 호출이 API await 지점에 도달하도록

      final second = await h.notifier.forceCompleteOrder(a);

      expect(second, isFalse,
          reason: 'in-flight 거절은 반드시 false — true 면 호출부가 "성공" 로그를 남긴다');
      expect(h.api.forceCalls.length, 1);

      gate.complete(_forceAllSuccess(const ['A']));
      expect(await first, isTrue);
    });

    test('예외로 끝나도 락이 풀려 다시 시도할 수 있다', () async {
      final h = await _buildProvider();
      final a = _order(orderNo: 'A', status: OrderStatus.PREPARING);
      h.api.forceThrows = StateError('boom');

      expect(await h.notifier.forceCompleteOrder(a), isFalse);
      expect(await h.notifier.forceCompleteOrder(a), isFalse);

      // 실패 후 운영자가 다시 누르는 것은 정당한 요청이다.
      expect(h.api.forceCalls.length, 2);
    });
  });

  group('(i) 사운드그래프 전송 — 접수 주체가 앱이든 키오스크든 주문당 1회', () {
    // 매머드(MMTH/MHST) 전용 외부 통합. hook 자체의 브랜드 게이팅은
    // soundGraphHookProvider 가 하고, 여기서는 "언제 몇 번 발화하는가"만 고정한다.
    test('자가 자동접수 성공 시 1회 발화한다 (기존 동작)', () async {
      await PreferenceService().setAutoReceipt(true);
      addTearDown(() => PreferenceService().setAutoReceipt(false));

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1600);

      expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
      expect(h.soundGraph.acceptedOrderIds, ['A']);
    });

    test('접수 PUT 이 실패하면 발화하지 않는다', () async {
      await PreferenceService().setAutoReceipt(true);
      addTearDown(() => PreferenceService().setAutoReceipt(false));

      final h = await _buildProvider();
      h.api.updateOrderStatusResult = false;
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1600);

      // 서버가 거절한 주문을 KDS 로 보내면 실재하지 않는 주문이 뜬다.
      expect(h.soundGraph.acceptedOrderIds, isEmpty);
    });

    test('생성 시점부터 PREPARING 인 주문은 접수 없이도 발화한다', () async {
      // NICE_KIOSK 처럼 결제와 동시에 접수되는 유형. 앱이 접수 단계를 거치지
      // 않으므로, 이 진입점이 없으면 사운드그래프 KDS 로 영영 넘어가지 않는다.
      final h = await _buildProvider();
      final accepted = _order(
        orderNo: 'A',
        status: OrderStatus.PREPARING,
        source: 'NICE_KIOSK',
      );

      h.notifier.notifyExternallyAcceptedOrder(accepted);

      expect(h.soundGraph.acceptedOrderIds, ['A']);
      // 접수는 이미 끝난 주문이므로 PUT 은 나가지 않는다.
      expect(h.api.statusUpdates, isEmpty);
    });

    test('같은 주문이 두 경로로 잡혀도 전송은 1회뿐이다', () async {
      await PreferenceService().setAutoReceipt(true);
      addTearDown(() => PreferenceService().setAutoReceipt(false));

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A'));
      await _wait(1600);
      expect(h.soundGraph.acceptedOrderIds, ['A']);

      // 자가 접수로 이미 보낸 주문에 외부 접수 경로가 뒤늦게 걸려도 중복 금지.
      h.notifier.notifyExternallyAcceptedOrder(
        _order(orderNo: 'A', status: OrderStatus.PREPARING),
      );

      expect(h.soundGraph.acceptedOrderIds, ['A']);
    });
  });

  group('(h) 키오스크 노출 OFF — 접수는 하되 화면·출력에는 내보내지 않는다', () {
    // 노출 설정은 '화면에 보일지'만 정하고 '접수할지'는 정하지 않는다.
    // 접수까지 막히면 주문이 서버에 NEW 로 방치되고, 매머드 매장에서는
    // 사운드그래프 전송(접수에 실린 부수효과)까지 함께 누락된다.
    setUp(() async {
      await PreferenceService().setShowKioskOrder(false);
      await PreferenceService().setKioskPrintAndSound(false);
      await PreferenceService().setKioskAlwaysAutoAccept(true);
    });

    // setUpAll 이 깔아둔 이 파일의 공통 전제(노출 ON)로 되돌린다.
    tearDown(() async {
      await PreferenceService().setShowKioskOrder(true);
    });

    test('소켓 유입: 자동접수 PUT 은 나가고, 카드는 화면에 뜨지 않는다', () async {
      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A', source: 'WALD_KIOSK'));
      await _wait(1600);

      // 접수는 된다 — 노출 필터는 자동접수 체인 밖에 있어야 한다.
      expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
      // 화면에는 남지 않는다. 접수 직후 즉시 UI 업데이트가 필터를 건너뛰면
      // 카드가 한 번 떴다가 다음 폴링에서 사라지는 깜빡임이 된다 (회귀 방지).
      expect(h.container.read(orderProvider).orders, isEmpty);
      // 주문서·알림소리 OFF 이므로 출력 큐에도 들어가지 않는다.
      expect(h.output.addedOrderIds, isEmpty);
    });

    test('폴링 유입: 노출 OFF 여도 자동접수 대상에서 빠지지 않는다', () async {
      // refreshOrders 가 자동접수 판정에 필터 전 목록을 쓰는지 검증. 필터된
      // 목록을 쓰면 이 주문은 영영 접수되지 않는다(소켓이 놓쳤을 때의 안전망 상실).
      final h = await _buildProvider(
        initialServerOrders: [_order(orderNo: 'A', source: 'WALD_KIOSK')],
      );

      expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
      expect(h.container.read(orderProvider).orders, isEmpty);
      // 폴링 경로도 소켓 경로와 같은 출력 게이트를 타야 한다.
      expect(h.output.addedOrderIds, isEmpty);
    });

    test('노출 OFF 라도 주문서·알림소리 ON 이면 출력은 나간다 (두 축은 별개)', () async {
      await PreferenceService().setKioskPrintAndSound(true);
      addTearDown(() => PreferenceService().setKioskPrintAndSound(false));

      final h = await _buildProvider(
        initialServerOrders: [_order(orderNo: 'A', source: 'WALD_KIOSK')],
      );

      expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
      expect(h.output.addedOrderIds, contains('A'));
      // 출력이 나가도 화면 노출은 여전히 OFF 다.
      expect(h.container.read(orderProvider).orders, isEmpty);
    });

    // 버블·앱바는 '주문 카드를 보라'는 포인터라 노출 축을 따른다. 소리와 같은 축에
    // 묶으면, 카드가 목록에 없는데 버블만 깜빡여 점주가 눌러도 볼 게 없는 상태가 된다.
    // (Windows 버블 점멸은 종료 조건 없는 Timer 라 누를 때까지 계속 깜빡인다)
    test('노출 OFF + 소리 ON — 소리는 울리되 버블·앱바는 뜨지 않는다', () async {
      await PreferenceService().setKioskPrintAndSound(true);
      addTearDown(() => PreferenceService().setKioskPrintAndSound(false));

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A', source: 'WALD_KIOSK'));
      await _wait(1600);

      expect(h.alerts.calls, isNotEmpty);
      final call = h.alerts.calls.first;
      expect(call.sound, isTrue, reason: '주문서·알림소리 ON 이므로 소리는 울려야 한다');
      expect(call.overlay, isFalse, reason: '노출 OFF — 가리킬 카드가 없다');
      expect(call.appBar, isFalse, reason: '노출 OFF — 가리킬 카드가 없다');
    });

    test('노출 ON + 소리 OFF — 버블·앱바는 뜨되 소리는 나지 않는다', () async {
      await PreferenceService().setShowKioskOrder(true);

      final h = await _buildProvider();
      h.notifier.queueOrderExternal(_order(orderNo: 'A', source: 'WALD_KIOSK'));
      await _wait(1600);

      expect(h.alerts.calls, isNotEmpty);
      final call = h.alerts.calls.first;
      expect(call.sound, isFalse, reason: '주문서·알림소리 OFF');
      expect(call.overlay, isTrue, reason: '노출 ON — 카드가 뜨므로 버블도 가리켜야 한다');
      expect(call.appBar, isTrue, reason: '노출 ON — 카드가 뜨므로 앱바도 깜빡여야 한다');
    });
  });
}
