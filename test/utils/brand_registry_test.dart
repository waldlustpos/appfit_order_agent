import 'package:appfit_order_agent/constants/brand_theme.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/currency_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrandRegistry.resolveOrNull (capability/통화/환경용 — fallback 없음)', () {
    test('TPCP prefix → tpcp 메타', () {
      final b = BrandRegistry.resolveOrNull('TPCP0001');
      expect(b?.key, BrandKey.tpcp);
    });

    test('MHST prefix → mhst 메타', () {
      expect(BrandRegistry.resolveOrNull('MHST123')?.key, BrandKey.mhst);
    });

    test('MATA prefix → mata 메타', () {
      expect(BrandRegistry.resolveOrNull('MATA999')?.key, BrandKey.mata);
    });

    test('소문자 ID 도 대문자로 정규화되어 매칭', () {
      expect(BrandRegistry.resolveOrNull('tpcp0001')?.key, BrandKey.tpcp);
    });

    test('미지의 prefix(kokonut 등) → null (TPCP fallback 금지)', () {
      expect(BrandRegistry.resolveOrNull('KOKO0001'), isNull);
    });

    test('null/빈 ID → null', () {
      expect(BrandRegistry.resolveOrNull(null), isNull);
      expect(BrandRegistry.resolveOrNull(''), isNull);
    });
  });

  group('BrandRegistry.resolve (자산용 — fallback=tokyoplatz)', () {
    test('미지의 매장도 fallback(tpcp) 반환 — 로고 보장', () {
      expect(BrandRegistry.resolve('KOKO0001').key, BrandKey.tpcp);
      expect(BrandRegistry.resolve(null).key, BrandKey.tpcp);
    });

    test('fallback 은 tokyoplatz 자산', () {
      expect(BrandRegistry.fallback.assetFolder, 'tokyoplatz');
    });
  });

  group('capability 매핑 (사운드그래프 크로스-브랜드 누수 차단의 근거)', () {
    test('라벨 카테고리 필터는 TPCP 만', () {
      expect(
          BrandRegistry.byKey(BrandKey.tpcp)
              .has(BrandFeature.labelCategoryFilter),
          isTrue);
      expect(
          BrandRegistry.byKey(BrandKey.mhst)
              .has(BrandFeature.labelCategoryFilter),
          isFalse);
      expect(
          BrandRegistry.byKey(BrandKey.mata)
              .has(BrandFeature.labelCategoryFilter),
          isFalse);
    });

    test('사운드그래프 전송은 MHST 만 (TPCP/MATA 는 false → 누수 차단)', () {
      expect(
          BrandRegistry.byKey(BrandKey.mhst).has(BrandFeature.soundGraphSend),
          isTrue);
      expect(
          BrandRegistry.byKey(BrandKey.tpcp).has(BrandFeature.soundGraphSend),
          isFalse);
      expect(
          BrandRegistry.byKey(BrandKey.mata).has(BrandFeature.soundGraphSend),
          isFalse);
    });

    test('자동 업데이트 강제는 TPCP 만', () {
      expect(
          BrandRegistry.byKey(BrandKey.tpcp).has(BrandFeature.autoUpdateForce),
          isTrue);
      expect(
          BrandRegistry.byKey(BrandKey.mhst).has(BrandFeature.autoUpdateForce),
          isFalse);
    });
  });

  group('통화/환경/테마/영수증로고 매핑', () {
    test('통화: TPCP=jpy, MHST/MATA=krw', () {
      expect(BrandRegistry.byKey(BrandKey.tpcp).currency, CurrencyUnit.jpy);
      expect(BrandRegistry.byKey(BrandKey.mhst).currency, CurrencyUnit.krw);
      expect(BrandRegistry.byKey(BrandKey.mata).currency, CurrencyUnit.krw);
    });

    test('서버 환경: TPCP=japanLive, 그 외=live', () {
      expect(BrandRegistry.byKey(BrandKey.tpcp).serverEnvironment, 'japanLive');
      expect(BrandRegistry.byKey(BrandKey.mhst).serverEnvironment, 'live');
      expect(BrandRegistry.byKey(BrandKey.mata).serverEnvironment, 'live');
    });

    test('테마 매핑', () {
      expect(
          BrandRegistry.byKey(BrandKey.tpcp).theme, BrandTheme.appfitDefault);
      expect(
          BrandRegistry.byKey(BrandKey.mhst).theme, BrandTheme.mammothCoffee);
      expect(BrandRegistry.byKey(BrandKey.mata).theme, BrandTheme.mata);
    });

    test('영수증 로고: TPCP 없음, MHST/MATA 있음', () {
      expect(BrandRegistry.byKey(BrandKey.tpcp).hasReceiptLogo, isFalse);
      expect(BrandRegistry.byKey(BrandKey.tpcp).receiptLogoPath, isNull);
      expect(BrandRegistry.byKey(BrandKey.mhst).hasReceiptLogo, isTrue);
      expect(BrandRegistry.byKey(BrandKey.mhst).receiptLogoPath, isNotNull);
    });

    test('자산 경로 포맷', () {
      final mhst = BrandRegistry.byKey(BrandKey.mhst);
      expect(mhst.labelLogoPath, 'assets/images/brand/mammoth/label_logo.bmp');
      expect(
          mhst.receiptLogoPath, 'assets/images/brand/mammoth/receipt_logo.png');
    });
  });
}
