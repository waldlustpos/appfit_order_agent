import 'package:appfit_order_agent/core/products/product_grouping.dart';
import 'package:appfit_order_agent/core/products/shop_catalog_parser.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/v0/shops/{shopCode}/categories/items` 응답 파싱 고정 테스트.
///
/// 이 엔드포인트는 옵션을 **상품×옵션그룹마다 반복해서** 내려준다. 구 `/categories`
/// 의 매장 전역 평면 `options[]` 와 결정적으로 다른 성질이라, 아래 불변식이
/// 깨지면 곧바로 운영 사고가 된다.
///  - 같은 옵션이 N번 등장해도 '옵션' 버킷에는 1건만 남는다.
///  - 옵션의 categoryCode 는 부모 옵션그룹의 `optionGroupPosId` 다(구 migration 조인 대체).
///  - 옵션명은 `name` 키에서 온다(구 응답의 `optionName` 이 아니다).
///  - 상품 0개 카테고리는 categories 에 남는다(상품관리 좌측 목록 정본).

Map<String, dynamic> _option({
  required String id,
  required String posId,
  required String name,
  int price = 500,
  String status = 'ON_SALE',
  int displayOrder = 0,
}) =>
    {
      'optionId': id,
      'optionPosId': posId,
      'name': name,
      'salePrice': price,
      'status': status,
      'displayOrder': displayOrder,
      'isDefault': false,
      'isChangeable': true,
      'maxQuantity': 3,
    };

Map<String, dynamic> _group({
  required String posId,
  required String name,
  required List<Map<String, dynamic>> options,
  int displayOrder = 0,
}) =>
    {
      'optionGroupId': 'uuid-group-$posId',
      'optionGroupPosId': posId,
      'name': name,
      'displayOrder': displayOrder,
      'uiButtonType': 'RADIO',
      'optionGroupType': 'DEFAULT',
      'minSelection': 0,
      'maxSelection': 1,
      'options': options,
    };

Map<String, dynamic> _item({
  required String shopItemId,
  required String itemPosId,
  required String name,
  int price = 4500,
  String status = 'ON_SALE',
  int displayOrder = 0,
  List<Map<String, dynamic>> optionGroups = const [],
}) =>
    {
      'shopItemId': shopItemId,
      'itemPosId': itemPosId,
      'itemName': name,
      'salePrice': price,
      'status': status,
      'imageUrls': <String>[],
      'displayOrder': displayOrder,
      'optionGroups': optionGroups,
    };

Map<String, dynamic> _category({
  required String posId,
  required String name,
  required List<Map<String, dynamic>> items,
  int displayOrder = 0,
}) =>
    {
      'categoryId': 'uuid-cat-$posId',
      'categoryPosId': posId,
      'categoryName': name,
      'displayOrder': displayOrder,
      'items': items,
    };

Map<String, dynamic> _data(List<Map<String, dynamic>> categories) =>
    {'shopName': '테스트매장', 'categories': categories};

List<ProductModel> _options(List<ProductModel> products) =>
    products.where((p) => p.type == ProductType.option).toList();

List<ProductModel> _items(List<ProductModel> products) =>
    products.where((p) => p.type == ProductType.item).toList();

void main() {
  group('옵션 dedupe', () {
    test('같은 optionId 가 여러 상품/그룹에 반복 등장해도 1건으로 접힌다', () {
      final shot = _option(id: 'opt-shot', posId: 'POS-SHOT', name: '샷 추가');
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP001', name: '샷', options: [shot]),
            ],
          ),
          _item(
            shopItemId: 'item-2',
            itemPosId: 'POS-2',
            name: '라떼',
            optionGroups: [
              _group(posId: 'TKP001', name: '샷', options: [shot]),
            ],
          ),
          _item(
            shopItemId: 'item-3',
            itemPosId: 'POS-3',
            name: '카푸치노',
            optionGroups: [
              _group(posId: 'TKP001', name: '샷', options: [shot]),
            ],
          ),
        ]),
      ]);

      final result = parseShopCatalog(data);

      expect(_items(result.products), hasLength(3));
      expect(_options(result.products), hasLength(1));
      expect(_options(result.products).single.internalId, 'opt-shot');
      expect(_options(result.products).single.productId, 'POS-SHOT');
    });

    test('optionId 가 다르면 이름이 같아도 별건으로 남는다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP004', name: '온도', options: [
                _option(id: 'opt-hot', posId: 'POS-HOT', name: 'HOT'),
                _option(id: 'opt-ice', posId: 'POS-ICE', name: 'ICE'),
              ]),
            ],
          ),
        ]),
      ]);

      expect(_options(parseShopCatalog(data).products), hasLength(2));
    });

    test('optionId 가 비면 optionPosId 로 폴백해 서로 다른 옵션이 뭉개지지 않는다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP004', name: '온도', options: [
                _option(id: '', posId: 'POS-HOT', name: 'HOT'),
                _option(id: '', posId: 'POS-ICE', name: 'ICE'),
              ]),
            ],
          ),
        ]),
      ]);

      final options = _options(parseShopCatalog(data).products);
      expect(options, hasLength(2));
      expect(options.map((o) => o.productId), ['POS-HOT', 'POS-ICE']);
    });

    test('식별자가 전혀 없는 옵션은 스킵된다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP004', name: '온도', options: [
                _option(id: '', posId: '', name: '이름만 있음'),
                _option(id: 'opt-ice', posId: 'POS-ICE', name: 'ICE'),
              ]),
            ],
          ),
        ]),
      ]);

      final options = _options(parseShopCatalog(data).products);
      expect(options, hasLength(1));
      expect(options.single.productName, 'ICE');
    });

    test('중복 등장분의 값이 달라도 첫 등장 값이 유지된다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP001', name: '샷', options: [
                _option(
                    id: 'opt-shot',
                    posId: 'POS-SHOT',
                    name: '샷 추가',
                    price: 500),
              ]),
            ],
          ),
          _item(
            shopItemId: 'item-2',
            itemPosId: 'POS-2',
            name: '라떼',
            optionGroups: [
              _group(posId: 'TKP009', name: '샷(라떼)', options: [
                _option(
                  id: 'opt-shot',
                  posId: 'POS-SHOT',
                  name: '샷 추가',
                  price: 700,
                  status: 'SOLD_OUT',
                ),
              ]),
            ],
          ),
        ]),
      ]);

      final option = _options(parseShopCatalog(data).products).single;
      expect(option.menuPrice, 500);
      expect(option.status, ProductStatus.sale);
      expect(option.categoryCode, 'TKP001');
    });
  });

  group('옵션 필드 매핑', () {
    test('옵션명은 name 키에서 온다 (구 optionName 오매핑 회귀 방지)', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP001', name: '샷', options: [
                {
                  'optionId': 'opt-shot',
                  'optionPosId': 'POS-SHOT',
                  'name': '샷 추가',
                  // 구 응답의 키가 섞여 들어와도 name 이 이긴다.
                  'optionName': '잘못된 이름',
                  'salePrice': 500,
                  'status': 'ON_SALE',
                  'displayOrder': 0,
                },
              ]),
            ],
          ),
        ]),
      ]);

      expect(
          _options(parseShopCatalog(data).products).single.productName, '샷 추가');
    });

    test('옵션의 categoryCode 는 부모 그룹의 optionGroupPosId 다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            optionGroups: [
              _group(posId: 'TKP001', name: '원두', options: [
                _option(id: 'opt-bean', posId: 'POS-BEAN', name: '산미'),
              ]),
              _group(posId: 'TKP004', name: '온도', options: [
                _option(id: 'opt-ice', posId: 'POS-ICE', name: 'ICE'),
              ]),
            ],
          ),
        ]),
      ]);

      final options = _options(parseShopCatalog(data).products);
      expect(
        {for (final o in options) o.internalId: o.categoryCode},
        {'opt-bean': 'TKP001', 'opt-ice': 'TKP004'},
      );
    });

    test('옵션은 인공 카테고리 버킷에 들어가고 displayOrder 는 상품 뒤로 밀린다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(
            shopItemId: 'item-1',
            itemPosId: 'POS-1',
            name: '아메리카노',
            displayOrder: 3,
            optionGroups: [
              _group(posId: 'TKP004', name: '온도', options: [
                _option(id: 'opt-hot', posId: 'POS-HOT', name: 'HOT'),
                _option(id: 'opt-ice', posId: 'POS-ICE', name: 'ICE'),
              ]),
            ],
          ),
        ]),
      ]);

      final options = _options(parseShopCatalog(data).products);
      expect(options.map((o) => o.categoryName),
          everyElement(kOptionBucketCategoryName));
      expect(options.map((o) => o.displayOrder),
          [kOptionDisplayOrderBase, kOptionDisplayOrderBase + 1]);
      expect(_items(parseShopCatalog(data).products).single.displayOrder, 3);
    });
  });

  group('카테고리·상품', () {
    test('상품 0개 카테고리도 categories 에 남는다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(shopItemId: 'item-1', itemPosId: 'POS-1', name: '아메리카노'),
        ]),
        _category(posId: 'DX0001', name: '준비중', items: const []),
      ]);

      final result = parseShopCatalog(data);
      expect(result.categories.map((c) => c.categoryName), ['커피', '준비중']);
      expect(result.products, hasLength(1));
    });

    test('같은 상품이 두 카테고리에 등록되면 사본이 유지되고 카드는 1장으로 접힌다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          _item(shopItemId: 'item-1', itemPosId: 'POS-1', name: '아메리카노'),
        ]),
        _category(posId: 'DX0002', name: '추천', items: [
          _item(shopItemId: 'item-1', itemPosId: 'POS-1', name: '아메리카노'),
        ]),
      ]);

      final products = parseShopCatalog(data).products;
      expect(_items(products), hasLength(2));

      final groups = buildProductGroups(visibleProducts(products, ''));
      expect(groups, hasLength(1));
      expect(groups.single.categoryNames, ['커피', '추천']);
    });

    test('손상된 카테고리 1건은 스킵되고 나머지는 유지된다', () {
      final data = _data([
        // categoryName 누락 → ShopCategoryModel.fromJson 이 FormatException.
        {
          'categoryPosId': 'DX0009',
          'displayOrder': 0,
          'items': [
            _item(shopItemId: 'item-x', itemPosId: 'POS-X', name: '유실됨'),
          ],
        },
        _category(posId: 'DX0000', name: '커피', items: [
          _item(shopItemId: 'item-1', itemPosId: 'POS-1', name: '아메리카노'),
        ]),
      ]);

      final result = parseShopCatalog(data);
      expect(result.categories.map((c) => c.categoryName), ['커피']);
      expect(_items(result.products).map((p) => p.productName), ['아메리카노']);
    });

    test('식별자 없는 상품은 스킵되지만 같은 카테고리의 다른 상품은 남는다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          {
            'itemName': '식별자 없음',
            'salePrice': 1000,
            'status': 'ON_SALE',
            'displayOrder': 0,
          },
          _item(shopItemId: 'item-1', itemPosId: 'POS-1', name: '아메리카노'),
        ]),
      ]);

      expect(_items(parseShopCatalog(data).products).map((p) => p.productName),
          ['아메리카노']);
    });

    test('상품이 스킵돼도 그 상품에 달린 옵션은 버킷에 남는다', () {
      final data = _data([
        _category(posId: 'DX0000', name: '커피', items: [
          {
            'itemName': '식별자 없음',
            'salePrice': 1000,
            'status': 'ON_SALE',
            'displayOrder': 0,
            'optionGroups': [
              _group(posId: 'TKP004', name: '온도', options: [
                _option(id: 'opt-ice', posId: 'POS-ICE', name: 'ICE'),
              ]),
            ],
          },
        ]),
      ]);

      final result = parseShopCatalog(data);
      expect(_items(result.products), isEmpty);
      expect(_options(result.products).single.internalId, 'opt-ice');
    });

    test('categories 가 없거나 비어도 빈 결과를 돌려준다', () {
      expect(parseShopCatalog(<String, dynamic>{}).products, isEmpty);
      expect(parseShopCatalog(<String, dynamic>{}).categories, isEmpty);
      expect(parseShopCatalog(_data(const [])).categories, isEmpty);
    });
  });

  group('상태 매핑', () {
    test('AppFit 상태 코드가 ProductStatus 로 매핑된다', () {
      expect(productStatusFromAppFit('ON_SALE'), ProductStatus.sale);
      expect(productStatusFromAppFit('SALE'), ProductStatus.sale);
      expect(productStatusFromAppFit('SOLD_OUT'), ProductStatus.soldOut);
      expect(productStatusFromAppFit('DISCONTINUED'), ProductStatus.hidden);
      expect(productStatusFromAppFit('PENDING'), ProductStatus.hidden);
      // 모르는 값은 숨김으로 접는다 — 판매중으로 노출하는 것보다 안전하다.
      expect(productStatusFromAppFit('DELETED'), ProductStatus.hidden);
      expect(productStatusFromAppFit(''), ProductStatus.hidden);
    });
  });
}
