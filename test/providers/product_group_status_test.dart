import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 동일 상품명 그룹의 일괄 상태 변경(`updateProductsStatus`) 회귀 테스트.
///
/// 고정하는 불변식 두 가지:
///  1. 그룹이 몇 건이든 **PUT 1회**로 끝내고, 그 과정에서 카탈로그를 다시 GET 하지
///     않는다(과거 `updateItemStatus` 는 타입 판별만을 위해 전체 카탈로그를 재조회했다).
///  2. 낙관적 갱신은 **internalId** 로 매칭한다. 그룹 멤버는 POS ID 가 서로 다르고,
///     같은 상품이 여러 카테고리에 등록되면 목록에 사본이 여러 개 존재한다 —
///     productId 매칭으로는 사본 일부가 옛 상태로 남아 카드 표기가 어긋난다.

class _UpdateCall {
  _UpdateCall(this.storeId, this.type, this.internalIds, this.status);

  final String storeId;
  final ProductType type;
  final List<String> internalIds;
  final ProductStatus status;
}

class _FakeApiService implements ApiService {
  _FakeApiService(this._products);

  final List<ProductModel> _products;

  final List<String> catalogRequests = [];
  final List<_UpdateCall> updateCalls = [];

  /// 서버가 거부(200 아님)하는 상황을 흉내낸다.
  bool updateResult = true;

  /// 네트워크 예외를 흉내낸다.
  Object? updateThrows;

  @override
  Future<({List<ProductModel> products, List<ShopCategoryModel> categories})>
      getShopCatalog(String storeId) async {
    catalogRequests.add(storeId);
    return (products: _products, categories: <ShopCategoryModel>[]);
  }

  @override
  Future<bool> updateItemsStatus({
    required String storeId,
    required ProductType type,
    required List<String> internalIds,
    required ProductStatus status,
  }) async {
    updateCalls.add(_UpdateCall(storeId, type, internalIds, status));
    if (updateThrows != null) throw updateThrows!;
    return updateResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStore extends Store {
  _FakeStore(this._initial);

  final StoreModel? _initial;

  @override
  Future<StoreModel?> build() async => _initial;
}

ProductModel _p({
  required String internalId,
  required String productId,
  String name = '샷 추가',
  String categoryName = '옵션',
  int price = 500,
  ProductStatus status = ProductStatus.sale,
  ProductType type = ProductType.option,
  int displayOrder = 0,
}) =>
    ProductModel(
      productId: productId,
      productName: name,
      categoryName: categoryName,
      categoryCode: 'CAT',
      menuPrice: price,
      status: status,
      type: type,
      internalId: internalId,
      displayOrder: displayOrder,
    );

({ProviderContainer container, _FakeApiService api}) _build(
  List<ProductModel> products, {
  /// false 면 매장 미확정 상태(storeId 없음)를 흉내낸다.
  bool withStore = true,
}) {
  final api = _FakeApiService(products);
  final store = withStore
      ? StoreModel(storeId: 'TPCP00001', name: '테스트매장', isOpen: true)
      : null;
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    storeProvider.overrideWith(() => _FakeStore(store)),
  ]);
  addTearDown(container.dispose);
  return (container: container, api: api);
}

/// 상태 조회 헬퍼 — internalId 로 현재 상태를 읽는다.
ProductStatus _statusOf(ProviderContainer c, String internalId,
    {ProductType? type}) {
  return c
      .read(productProvider)
      .value!
      .firstWhere(
          (p) => p.internalId == internalId && (type == null || p.type == type))
      .status;
}

void main() {
  test('멤버가 몇 건이든 PUT 1회로 끝내고 카탈로그를 다시 조회하지 않는다', () async {
    final b = _build([
      _p(internalId: 'u1', productId: 'POS-1', price: 500),
      _p(internalId: 'u2', productId: 'POS-2', price: 700),
      _p(internalId: 'u3', productId: 'POS-3', price: 1000),
    ]);
    await b.container.read(productProvider.future);
    final catalogCallsBefore = b.api.catalogRequests.length;

    final ok =
        await b.container.read(productProvider.notifier).updateProductsStatus(
              type: ProductType.option,
              internalIds: const ['u1', 'u2', 'u3'],
              newStatus: ProductStatus.soldOut,
            );

    expect(ok, isTrue);
    expect(b.api.updateCalls, hasLength(1), reason: '그룹당 요청 1회');
    expect(b.api.updateCalls.single.internalIds, ['u1', 'u2', 'u3']);
    expect(b.api.updateCalls.single.type, ProductType.option);
    expect(b.api.updateCalls.single.status, ProductStatus.soldOut);
    expect(b.api.updateCalls.single.storeId, 'TPCP00001');
    expect(b.api.catalogRequests.length, catalogCallsBefore,
        reason: '타입 판별용 카탈로그 재조회는 제거됐다');
  });

  test('POS ID 가 서로 다른 멤버 전원이 갱신된다', () async {
    final b = _build([
      _p(internalId: 'u1', productId: 'POS-1', price: 500),
      _p(internalId: 'u2', productId: 'POS-2', price: 700),
    ]);
    await b.container.read(productProvider.future);

    await b.container.read(productProvider.notifier).updateProductsStatus(
          type: ProductType.option,
          internalIds: const ['u1', 'u2'],
          newStatus: ProductStatus.soldOut,
        );

    expect(_statusOf(b.container, 'u1'), ProductStatus.soldOut);
    expect(_statusOf(b.container, 'u2'), ProductStatus.soldOut);
  });

  test('같은 internalId 의 카테고리 사본이 둘 다 갱신된다', () async {
    // 같은 상품이 두 카테고리에 등록되면 카탈로그 평탄화에서 사본이 2건 생긴다.
    final b = _build([
      _p(
          internalId: 'same',
          productId: 'POS-1',
          categoryName: '커피',
          type: ProductType.item),
      _p(
          internalId: 'same',
          productId: 'POS-1',
          categoryName: '신메뉴',
          type: ProductType.item),
    ]);
    await b.container.read(productProvider.future);

    await b.container.read(productProvider.notifier).updateProductsStatus(
          type: ProductType.item,
          internalIds: const ['same'],
          newStatus: ProductStatus.soldOut,
        );

    final updated = b.container.read(productProvider).value!;
    expect(
        updated.where((p) => p.status == ProductStatus.soldOut), hasLength(2),
        reason: '사본 하나가 옛 상태로 남으면 좌측 카운트와 카드 표기가 어긋난다');
  });

  test('그룹 밖 상품은 건드리지 않는다', () async {
    final b = _build([
      _p(internalId: 'u1', productId: 'POS-1'),
      _p(internalId: 'other', productId: 'POS-9', name: '시럽 추가'),
    ]);
    await b.container.read(productProvider.future);

    await b.container.read(productProvider.notifier).updateProductsStatus(
          type: ProductType.option,
          internalIds: const ['u1'],
          newStatus: ProductStatus.soldOut,
        );

    expect(_statusOf(b.container, 'other'), ProductStatus.sale);
  });

  test('같은 UUID 라도 타입이 다르면 갱신하지 않는다', () async {
    final b = _build([
      _p(internalId: 'dup', productId: 'POS-1', type: ProductType.item),
      _p(internalId: 'dup', productId: 'POS-2', type: ProductType.option),
    ]);
    await b.container.read(productProvider.future);

    await b.container.read(productProvider.notifier).updateProductsStatus(
          type: ProductType.item,
          internalIds: const ['dup'],
          newStatus: ProductStatus.soldOut,
        );

    expect(_statusOf(b.container, 'dup', type: ProductType.item),
        ProductStatus.soldOut);
    expect(_statusOf(b.container, 'dup', type: ProductType.option),
        ProductStatus.sale,
        reason: 'UUID 네임스페이스가 겹쳐도 타입이 다르면 별개 레코드다');
  });

  test('서버가 거부하면 상태를 바꾸지 않고 false 를 돌려준다', () async {
    final b = _build([_p(internalId: 'u1', productId: 'POS-1')]);
    await b.container.read(productProvider.future);
    b.api.updateResult = false;

    final ok =
        await b.container.read(productProvider.notifier).updateProductsStatus(
              type: ProductType.option,
              internalIds: const ['u1'],
              newStatus: ProductStatus.soldOut,
            );

    expect(ok, isFalse);
    expect(_statusOf(b.container, 'u1'), ProductStatus.sale,
        reason: '실패했는데 화면만 품절로 보이면 점주가 품절됐다고 오인한다');
  });

  test('API 예외는 삼키고 상태를 유지한 채 false 를 돌려준다', () async {
    final b = _build([_p(internalId: 'u1', productId: 'POS-1')]);
    await b.container.read(productProvider.future);
    b.api.updateThrows = Exception('network down');

    final ok =
        await b.container.read(productProvider.notifier).updateProductsStatus(
              type: ProductType.option,
              internalIds: const ['u1'],
              newStatus: ProductStatus.soldOut,
            );

    expect(ok, isFalse);
    expect(_statusOf(b.container, 'u1'), ProductStatus.sale);
  });

  test('storeId 가 없으면 API 를 호출하지 않는다', () async {
    final b =
        _build([_p(internalId: 'u1', productId: 'POS-1')], withStore: false);
    await b.container.read(productProvider.future);

    final ok =
        await b.container.read(productProvider.notifier).updateProductsStatus(
              type: ProductType.option,
              internalIds: const ['u1'],
              newStatus: ProductStatus.soldOut,
            );

    expect(ok, isFalse);
    expect(b.api.updateCalls, isEmpty);
  });

  test('유효한 internalId 가 하나도 없으면 API 를 호출하지 않는다', () async {
    final b = _build([_p(internalId: '', productId: 'POS-1')]);
    await b.container.read(productProvider.future);

    final ok =
        await b.container.read(productProvider.notifier).updateProductsStatus(
              type: ProductType.option,
              internalIds: const ['', ''],
              newStatus: ProductStatus.soldOut,
            );

    expect(ok, isFalse);
    expect(b.api.updateCalls, isEmpty, reason: '빈 UUID 는 서버가 거부한다');
  });
}
