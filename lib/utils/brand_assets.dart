import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';

/// 현재 브랜드의 인쇄 자산(라벨/영수증 로고) 경로를 노출하는 얇은 파사드.
///
/// 브랜드 식별·메타데이터는 [BrandRegistry](단일 출처)에 위임한다. 본 클래스는
/// label_painter / external_receipt_printer 의 lazy invalidation 호출부가 쓰는
/// 정적 getter 만 제공한다(매 호출마다 현재 매장 ID 로 재해석 → 매장 전환 시 자동 반영).
///
/// 새 브랜드 추가 절차는 [BrandRegistry] 주석 참고.
class BrandAssets {
  BrandAssets._();

  static BrandMeta _current() =>
      BrandRegistry.resolve(PreferenceService().getId());

  static String? get labelLogoPath => _current().labelLogoPath;

  static String get labelLogoFallbackPath =>
      BrandRegistry.fallback.labelLogoPath!;

  static double get labelLogoWidth => _current().labelLogoWidth;

  static String? get receiptLogoPath => _current().receiptLogoPath;
}
