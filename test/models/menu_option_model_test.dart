import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 옵션 그룹(= 옵션 카테고리) 3필드는 **v1 주문상세 응답에만** 존재한다.
/// v0 응답에는 없으므로 null 로 떨어져야 하고, 라벨 sub-info 분류의 정본인
/// [MenuOptionModel.optionGroupPosId] 는 캐시 왕복에서도 보존돼야 한다.
void main() {
  group('MenuOptionModel 옵션그룹 파싱 (v1)', () {
    test('v1 응답 — 옵션그룹 3필드를 읽는다', () {
      final opt = MenuOptionModel.fromJson(const {
        'shopOptionId': '0pp75p4cgxabf',
        'optionName': 'L',
        'optionPrice': 0.0,
        'qty': 1,
        'optionGroupId': '0q341bfbaa2eq',
        'optionGroupPosId': 'TKP004',
        'optionGroupName': 'サイズを選ぶ',
        'itemPosId': 'M009000',
      });

      expect(opt.shopOptionId, '0pp75p4cgxabf');
      expect(opt.optionName, 'L');
      expect(opt.optionGroupId, '0q341bfbaa2eq');
      expect(opt.optionGroupPosId, 'TKP004');
      expect(opt.optionGroupName, 'サイズを選ぶ');
      expect(opt.itemPosId, 'M009000');
    });

    test('v0 응답 — 옵션그룹 필드가 없으면 null', () {
      final opt = MenuOptionModel.fromJson(const {
        'shopOptionId': '0pp75dj43y6de',
        'optionName': 'Only ICE',
        'optionPrice': 0.0,
        'qty': 1,
      });

      expect(opt.optionName, 'Only ICE');
      expect(opt.optionGroupId, isNull);
      expect(opt.optionGroupPosId, isNull);
      expect(opt.optionGroupName, isNull);
      expect(opt.itemPosId, isNull);
    });

    test('toJson → fromJson 왕복에서 옵션그룹이 보존된다 (캐시 경로)', () {
      final original = MenuOptionModel(
        shopOptionId: 'o1',
        optionName: 'ダーク',
        optionPrice: 0,
        qty: 1,
        optionGroupId: 'g1',
        optionGroupPosId: 'TKP012',
        optionGroupName: '豆の種類選択',
        itemPosId: 'M009000',
      );

      final restored = MenuOptionModel.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.optionGroupPosId, 'TKP012');
      expect(restored.itemPosId, 'M009000');
    });

    test('옵션그룹 없는 옵션의 toJson 은 해당 키를 넣지 않는다', () {
      final opt = MenuOptionModel(
        shopOptionId: 'o1',
        optionName: '샷 추가',
        optionPrice: 500,
        qty: 1,
      );

      final json = opt.toJson();

      expect(json.containsKey('optionGroupId'), isFalse);
      expect(json.containsKey('optionGroupPosId'), isFalse);
      expect(json.containsKey('optionGroupName'), isFalse);
      expect(json.containsKey('itemPosId'), isFalse);
      expect(MenuOptionModel.fromJson(json), opt);
    });

    test('옵션그룹이 다르면 서로 다른 값으로 취급한다', () {
      MenuOptionModel withGroup(String? group) => MenuOptionModel(
            shopOptionId: 'o1',
            optionName: 'L',
            optionPrice: 0,
            qty: 1,
            optionGroupPosId: group,
          );

      expect(withGroup('TKP004'), isNot(withGroup('TKP009')));
      expect(withGroup('TKP004'), isNot(withGroup(null)));
      expect(withGroup('TKP004'), withGroup('TKP004'));
      expect(withGroup('TKP004').hashCode, withGroup('TKP004').hashCode);
    });

    test('itemPosId 가 다르면 서로 다른 값으로 취급한다', () {
      MenuOptionModel withItemPosId(String? posId) => MenuOptionModel(
            shopOptionId: 'o1',
            optionName: 'L',
            optionPrice: 0,
            qty: 1,
            itemPosId: posId,
          );

      expect(withItemPosId('M009000'), isNot(withItemPosId('M009001')));
      expect(withItemPosId('M009000'), isNot(withItemPosId(null)));
      expect(withItemPosId('M009000'), withItemPosId('M009000'));
      expect(
          withItemPosId('M009000').hashCode, withItemPosId('M009000').hashCode);
    });
  });
}
