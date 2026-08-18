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

    test('MMTH prefix(매머드 운영) → mammoth 메타', () {
      expect(BrandRegistry.resolveOrNull('MMTH00001')?.key, BrandKey.mammoth);
    });

    test('MHST prefix(매머드 스테이징) → 같은 mammoth 메타', () {
      expect(BrandRegistry.resolveOrNull('MHST123')?.key, BrandKey.mammoth);
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
          BrandRegistry.byKey(BrandKey.mammoth)
              .has(BrandFeature.labelCategoryFilter),
          isFalse);
      expect(
          BrandRegistry.byKey(BrandKey.mata)
              .has(BrandFeature.labelCategoryFilter),
          isFalse);
    });

    test('사운드그래프 전송은 매머드 만 (TPCP/MATA 는 false → 누수 차단)', () {
      expect(
          BrandRegistry.byKey(BrandKey.mammoth).has(BrandFeature.soundGraphSend),
          isTrue);
      expect(
          BrandRegistry.byKey(BrandKey.tpcp).has(BrandFeature.soundGraphSend),
          isFalse);
      expect(
          BrandRegistry.byKey(BrandKey.mata).has(BrandFeature.soundGraphSend),
          isFalse);
    });

    test('Sunmi App Store 채널(OTA OFF)은 매머드 만 (TPCP/MATA 는 false → OTA)', () {
      expect(
          BrandRegistry.byKey(BrandKey.mammoth)
              .has(BrandFeature.sunmiAppStoreUpdate),
          isTrue);
      expect(
          BrandRegistry.byKey(BrandKey.tpcp)
              .has(BrandFeature.sunmiAppStoreUpdate),
          isFalse);
      expect(
          BrandRegistry.byKey(BrandKey.mata)
              .has(BrandFeature.sunmiAppStoreUpdate),
          isFalse);
    });
  });

  group('통화/환경/테마/영수증로고 매핑', () {
    test('통화: TPCP=jpy, 매머드/MATA=krw', () {
      expect(BrandRegistry.byKey(BrandKey.tpcp).currency, CurrencyUnit.jpy);
      expect(BrandRegistry.byKey(BrandKey.mammoth).currency, CurrencyUnit.krw);
      expect(BrandRegistry.byKey(BrandKey.mata).currency, CurrencyUnit.krw);
    });

    test('서버 환경: TPCP=japanLive, MATA=live', () {
      expect(BrandRegistry.environmentForStoreId('TPCP0001'), 'japanLive');
      expect(BrandRegistry.environmentForStoreId('MATA999'), 'live');
    });

    test('테마 매핑', () {
      expect(
          BrandRegistry.byKey(BrandKey.tpcp).theme, BrandTheme.appfitDefault);
      expect(
          BrandRegistry.byKey(BrandKey.mammoth).theme, BrandTheme.mammothCoffee);
      expect(BrandRegistry.byKey(BrandKey.mata).theme, BrandTheme.mata);
    });

    test('영수증 로고: TPCP 없음, 매머드/MATA 있음', () {
      expect(BrandRegistry.byKey(BrandKey.tpcp).hasReceiptLogo, isFalse);
      expect(BrandRegistry.byKey(BrandKey.tpcp).receiptLogoPath, isNull);
      expect(BrandRegistry.byKey(BrandKey.mammoth).hasReceiptLogo, isTrue);
      expect(BrandRegistry.byKey(BrandKey.mammoth).receiptLogoPath, isNotNull);
    });

    test('자산 경로 포맷', () {
      final mammoth = BrandRegistry.byKey(BrandKey.mammoth);
      expect(
          mammoth.labelLogoPath, 'assets/images/brand/mammoth/label_logo.bmp');
      expect(mammoth.receiptLogoPath,
          'assets/images/brand/mammoth/receipt_logo.png');
    });
  });

  // 한 브랜드가 프리픽스를 여러 개 갖는 유일한 사례. MMTH 가 없으면 MMTH 매장이
  // resolveOrNull=null 로 떨어져 사운드그래프 OFF·테마 미적용이 되고, resolve()
  // 폴백 때문에 라벨·영수증에 tokyoplatz 로고가 찍힌다(출시 차단급 결함).
  group('매머드 다중 프리픽스 (MMTH=운영, MHST=스테이징)', () {
    test('MMTH → live, MHST → staging', () {
      expect(BrandRegistry.environmentForStoreId('MMTH00001'), 'live');
      expect(BrandRegistry.environmentForStoreId('MHST00001'), 'staging');
    });

    test('두 프리픽스가 같은 브랜드·같은 자산·같은 capability 로 해석된다', () {
      final live = BrandRegistry.resolveOrNull('MMTH00001')!;
      final staging = BrandRegistry.resolveOrNull('MHST00001')!;
      expect(live.key, staging.key);
      expect(live.assetFolder, staging.assetFolder);
      expect(live.theme, staging.theme);
      expect(live.currency, staging.currency);
      expect(live.features, staging.features);
      expect(live.labelLogoPath, 'assets/images/brand/mammoth/label_logo.bmp');
      expect(staging.labelLogoPath, live.labelLogoPath);
    });

    test('대표 프리픽스는 MMTH (선언 순서 = 운영 우선)', () {
      expect(BrandRegistry.byKey(BrandKey.mammoth).storeIdPrefix, 'MMTH');
    });

    test('타 브랜드 ID 를 넘기면 대표 프리픽스 환경으로 폴백', () {
      expect(
          BrandRegistry.byKey(BrandKey.mammoth).environmentFor('TPCP0001'),
          'live');
      expect(BrandRegistry.byKey(BrandKey.mammoth).environmentFor(null), 'live');
    });

    test('미등록 prefix 는 여전히 null (환경 폴백은 호출 측 책임)', () {
      expect(BrandRegistry.environmentForStoreId('KOKO0001'), isNull);
    });
  });
}
