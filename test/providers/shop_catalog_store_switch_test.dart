import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// shopCatalog 의 매장 전환 안전성 회귀 테스트.
///
/// Sentry 62c783…5928aaa9a514: PAIK00001 로그아웃 → TPCP00001 로그인 시
/// shopCatalog 가 이전 매장(PAIK00001)으로 categories 를 조회해 404 NOT_FOUND_SHOP
/// 이 발생했다. 원인은 매장 스코프 keepAlive 프로바이더 잔존 + 로딩 중
/// AsyncValue.value 가 유지하는 이전 매장 값으로의 조회. 아래 테스트는
///  (1) 매장 전환 후 항상 새 매장으로만 조회하고,
///  (2) storeProvider 로딩 중에는 이전 매장(.value)으로 조회하지 않고 settled 값을
///      기다리는지
/// 를 고정한다.

/// getShopCatalog 로 요청된 storeId 를 기록하는 fake. 나머지 멤버는 미사용.
class _FakeApiService implements ApiService {
  final List<String> catalogRequests = [];

  @override
  Future<({List<ProductModel> products, List<ShopCategoryModel> categories})>
      getShopCatalog(String storeId) async {
    catalogRequests.add(storeId);
    return (products: <ProductModel>[], categories: <ShopCategoryModel>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// storeProvider 오버라이드용 fake. build 로 초기값을 주고, 테스트에서 매장 전환/
/// 로딩 상태를 런타임에 흉내낸다.
class _FakeStore extends Store {
  _FakeStore(this._initial);

  final StoreModel? _initial;

  @override
  Future<StoreModel?> build() async => _initial;

  /// 매장 확정(전환).
  void settle(StoreModel? model) => state = AsyncData(model);

  /// 실서비스의 setStoreModel 이 로딩 진입 시 만드는 상태를 흉내낸다:
  /// AsyncLoading 이지만 .value 는 직전(다른) 매장을 유지한다.
  void loadingWithPrevious() =>
      state = const AsyncLoading<StoreModel?>().copyWithPrevious(state);
}

StoreModel _store(String id) =>
    StoreModel(storeId: id, name: '테스트매장', isOpen: true);

({ProviderContainer container, _FakeApiService api, _FakeStore store}) _build(
    StoreModel? initial) {
  final api = _FakeApiService();
  final store = _FakeStore(initial);
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    storeProvider.overrideWith(() => store),
  ]);
  addTearDown(container.dispose);
  return (container: container, api: api, store: store);
}

void main() {
  test('매장 전환(PAIK→TPCP) 후 카탈로그는 새 매장으로만 조회한다', () async {
    final b = _build(_store('PAIK00001'));
    await b.container.read(storeProvider.future); // 초기 매장 settle

    // 1) PAIK 카탈로그 조회
    await b.container.read(shopCatalogProvider.future);
    expect(b.api.catalogRequests, ['PAIK00001']);

    // 2) 매장 전환 → 재조회
    b.store.settle(_store('TPCP00001'));
    await b.container.read(shopCatalogProvider.future);

    // 3) 전환 후엔 TPCP 로만, PAIK 재조회는 없다.
    expect(b.api.catalogRequests.where((s) => s == 'PAIK00001').length, 1,
        reason: '전환 후 이전 매장으로 재조회하면 안 됨');
    expect(b.api.catalogRequests.last, 'TPCP00001');
  });

  test('storeProvider 로딩 중에는 이전 매장(.value)으로 조회하지 않고 settled 값을 기다린다',
      () async {
    final b = _build(_store('PAIK00001'));
    await b.container.read(storeProvider.future);
    await b.container.read(shopCatalogProvider.future);
    expect(b.api.catalogRequests, ['PAIK00001']);

    // shopCatalog 를 활성 구독 → storeProvider 변화 시 자동 재빌드.
    b.container.listen(shopCatalogProvider, (_, __) {});

    // 로딩 진입: .value 는 여전히 PAIK 를 가리킨다(실전 setStoreModel 재현).
    b.store.loadingWithPrevious();
    expect(b.container.read(storeProvider).isLoading, isTrue);
    expect(b.container.read(storeProvider).value?.storeId, 'PAIK00001',
        reason: '전제 조건: 로딩 중 .value 가 이전 매장을 유지');

    // 이벤트 루프를 흘려 재빌드가 로딩 대기 지점까지 진행되게 한다.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 로딩 중에는 이전 매장(.value=PAIK)으로 stale 조회하지 않고 settled 값을 기다린다.
    expect(b.api.catalogRequests, ['PAIK00001'],
        reason: '로딩 중 이전 매장으로 stale 조회하면 안 됨');

    // settled(TPCP) → 최종 조회는 TPCP 로만.
    b.store.settle(_store('TPCP00001'));
    await b.container.read(shopCatalogProvider.future);
    expect(b.api.catalogRequests.where((s) => s == 'PAIK00001').length, 1);
    expect(b.api.catalogRequests.last, 'TPCP00001');
  });
}
