import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:flutter_test/flutter_test.dart';

ProductModel _p({
  required String productId,
  required String internalId,
  required String categoryName,
  String? name,
}) =>
    ProductModel(
      productId: productId,
      productName: name ?? productId,
      categoryName: categoryName,
      categoryCode: categoryName,
      menuPrice: 1000,
      status: ProductStatus.sale,
      type: ProductType.item,
      internalId: internalId,
      displayOrder: 0,
    );

void main() {
  group('dedupeProductsByIdentity', () {
    test('여러 카테고리에 걸친 같은 상품을 하나로 접는다', () {
      // 카탈로그는 categories[].items 를 평탄화해 만들어지므로, 한 상품이
      // 3개 카테고리에 속하면 3개 항목으로 들어온다.
      final products = [
        _p(productId: 'AME', internalId: 'uuid-ame', categoryName: '커피'),
        _p(productId: 'AME', internalId: 'uuid-ame', categoryName: '아이스'),
        _p(productId: 'AME', internalId: 'uuid-ame', categoryName: '베스트'),
        _p(productId: 'WAF', internalId: 'uuid-waf', categoryName: '디저트'),
      ];

      final result = dedupeProductsByIdentity(products);

      expect(result.length, 2);
      expect(result.map((p) => p.productId).toList(), ['AME', 'WAF']);
    });

    test('앞 항목을 남긴다 — 필터 후 호출하면 현재 카테고리가 보존된다', () {
      final products = [
        _p(productId: 'AME', internalId: 'uuid-ame', categoryName: '아이스'),
        _p(productId: 'AME', internalId: 'uuid-ame', categoryName: '커피'),
      ];

      expect(dedupeProductsByIdentity(products).single.categoryName, '아이스');
    });

    test('internalId 가 비면 productId 로 접는다', () {
      final products = [
        _p(productId: 'AME', internalId: '', categoryName: '커피'),
        _p(productId: 'AME', internalId: '', categoryName: '아이스'),
      ];

      expect(dedupeProductsByIdentity(products).length, 1);
    });

    test('식별자가 둘 다 비면 접지 않는다 (서로 다른 상품일 수 있음)', () {
      final products = [
        _p(productId: '', internalId: '', categoryName: '커피', name: 'A'),
        _p(productId: '', internalId: '', categoryName: '커피', name: 'B'),
      ];

      expect(dedupeProductsByIdentity(products).length, 2);
    });

    test('서로 다른 상품은 그대로 둔다', () {
      final products = [
        _p(productId: 'AME', internalId: 'uuid-ame', categoryName: '커피'),
        _p(productId: 'LAT', internalId: 'uuid-lat', categoryName: '커피'),
      ];

      expect(dedupeProductsByIdentity(products).length, 2);
    });

    test('빈 목록도 안전하다', () {
      expect(dedupeProductsByIdentity(const <ProductModel>[]), isEmpty);
    });
  });
}
